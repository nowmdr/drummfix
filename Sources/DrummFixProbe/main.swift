import Foundation
import CoreMIDI
import DrummFixCore

var client: MIDIClientRef = 0
try midiCheck(MIDIClientCreateWithBlock("DrummFix Probe" as CFString, &client, nil), "Create client")
defer { MIDIClientDispose(client) }
if CommandLine.arguments.contains("--test-loopback") {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DrummFix-test-\(UUID().uuidString)")
    let lock = try SessionLock(directory: directory)
    let journal = directory.appendingPathComponent("recovery.json")
    let helper = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("DrummFixGuard")
    var fixture: MIDIEndpointRef = 0
    try midiCheck(MIDISourceCreateWithProtocol(client, "DrummFix Test Fixture" as CFString, ._1_0, &fixture), "Fixture")
    let engine = try MIDIEngine(journal: journal)
    try engine.start(source: MIDISourceInfo(fixture), helper: helper)
    let captureLock = NSLock()
    var received: [UInt32] = []
    var timestamps: [UInt64] = []
    var observer: MIDIPortRef = 0
    try midiCheck(MIDIInputPortCreateWithProtocol(client, "Test observer" as CFString, ._1_0, &observer, { list, _ in
        captureLock.lock(); defer { captureLock.unlock() }
        forEachMIDIPacket(list) { timestamp, words in received.append(contentsOf: words); timestamps.append(timestamp) }
    }), "Observer")
    try midiCheck(MIDIPortConnectSource(observer, engine.output, nil), "Observe corrected source")
    let input: [UInt32] = [0x20B90400, 0x20992E2E, 0x20892E00,
                          0x20992C64, 0x20892C00, 0x20A92E7F, 0x20A9157F,
                          0x20B9047F, 0x20992E34, 0x20892E00,
                          0x20B90400, 0x20992E50, 0x20992E00]
    var expected = input
    expected[8] = 0x20992A34; expected[9] = 0x20892A00
    let timestamp = mach_absolute_time()
    try midiCheck(publishMIDI(fixture, timestamp: timestamp, words: input), "Publish fixture")
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    captureLock.lock()
    let captured = received
    let capturedTimestamps = timestamps
    captureLock.unlock()
    guard captured == expected, capturedTimestamps.allSatisfy({ $0 == timestamp }) else {
        fatalError("Loopback mismatch: \(captured.map { String($0, radix: 16) })")
    }
    print("PASS: hidden source → live CoreMIDI input → conversion → virtual output; exact events and timestamps")
    engine.setMuted(true)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    captureLock.lock(); received.removeAll(); captureLock.unlock()
    _ = publishMIDI(fixture, timestamp: mach_absolute_time(), words: input)
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    captureLock.lock(); let mutedCapture = received; captureLock.unlock()
    guard mutedCapture.isEmpty else { fatalError("Mute leaked notes") }
    print("PASS: mute preserves isolation and emits no fixture events")
    engine.setMuted(false)
    captureLock.lock(); received.removeAll(); captureLock.unlock()
    let large = Array(repeating: UInt32(0x20B90101), count: 1024)
    _ = publishMIDI(fixture, timestamp: mach_absolute_time(), words: large)
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    captureLock.lock(); let largeCapture = received; captureLock.unlock()
    guard largeCapture == large else { fatalError("Large packet truncated: \(largeCapture.count)") }
    engine.setDynamics(.moderate)
    captureLock.lock(); received.removeAll(); captureLock.unlock()
    let dynamicInput: [UInt32] = [0x20B9047F, 0x20992E14, 0x20892E00]
    _ = publishMIDI(fixture, timestamp: mach_absolute_time(), words: dynamicInput)
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    captureLock.lock(); let dynamicCapture = received; captureLock.unlock()
    let dynamicExpected: [UInt32] = [0x20B9047F,
                                     0x20992A00 | UInt32(HiHatDynamics.moderate.adjusted(20)),
                                     0x20892A00]
    guard dynamicCapture == dynamicExpected else { fatalError("Dynamics mismatch: \(dynamicCapture)") }
    print("PASS: live dynamics setting expands closed hi-hat velocity")
    let statistics = engine.snapshot()
    print(String(format: "PASS: 1024-word packet; callback mean %.3f ms, max %.3f ms (not audio latency)", statistics.meanProcessingMicroseconds / 1000, statistics.maxProcessingMicroseconds / 1000))
    try engine.stop()
    guard midiInteger(fixture, kMIDIPropertyPrivate) != 1 else { fatalError("Fixture stayed private") }
    MIDIPortDispose(observer)
    MIDIEndpointDispose(fixture)
    withExtendedLifetime(lock) {}
    print("PASS: stop restores source visibility")
    exit(0)
}
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--test-isolation", let id = Int32(CommandLine.arguments[2]) {
    let lock = try SessionLock()
    guard try restoreIsolation(), let source = findSource(id: id) else { fatalError("Source/recovery unavailable") }
    let helper = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("DrummFixGuard")
    let lease = IsolationLease()
    var input: MIDIPortRef = 0
    try midiCheck(MIDIInputPortCreateWithProtocol(client, "Probe input" as CFString, ._1_0, &input, { _, _ in }), "Input")
    try midiCheck(MIDIPortConnectSource(input, source.endpoint, nil), "Connect")
    defer { MIDIPortDispose(input); try? lease.release(); withExtendedLifetime(lock) {} }
    try lease.acquire(source, helper: helper)
    print("ISOLATED: fresh external client cannot enumerate \(source.name). Guardian alive: \(lease.guardianAlive)")
    if CommandLine.arguments.contains("--hold") {
        print("HOLDING pid=\(getpid())"); fflush(stdout)
        RunLoop.current.run(until: Date().addingTimeInterval(60))
    }
    try lease.release()
    guard findSource(id: id)?.isPrivate == false else { fatalError("Not restored") }
    print("RESTORED: \(source.name)")
    exit(0)
}
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--is-visible", let id = Int32(CommandLine.arguments[2]) {
    exit(visibleSources().contains { $0.id == id } ? 0 : 1)
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(data: try encoder.encode(["visible": visibleSources(), "hardware": hardwareSources()]), encoding: .utf8)!)
