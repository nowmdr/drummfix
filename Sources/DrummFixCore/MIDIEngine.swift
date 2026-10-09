import Foundation
import CoreMIDI

public struct EngineSnapshot {
    public let running: Bool
    public let muted: Bool
    public let pedal: PedalState
    public let correctedHits: Int
    public let totalHits: Int
    public let unknownHits: Int
    public let lastHit: Date?
    public let traces: [MIDITrace]
    public let meanProcessingMicroseconds: Double
    public let maxProcessingMicroseconds: Double
    public let error: String?
}

/// The CoreMIDI receive callback processes and forwards immediately; UI polls snapshots.
/// A single short lock protects state. No UI work or disk writes occur in the callback.
public final class MIDIEngine {
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    public private(set) var output: MIDIEndpointRef = 0
    public private(set) var connectedSource: MIDISourceInfo?
    private let lock = NSLock()
    private var transformer = HiHatTransformer()
    private var dynamics: HiHatDynamics = .original
    private var running = false
    private var muted = false
    private var lastHit: Date?
    private var traces: [MIDITrace] = []
    private var traceID: UInt64 = 0
    private var totalProcessing: Double = 0
    private var maxProcessing: Double = 0
    private var packetCount: UInt64 = 0
    private var error: String?
    private let lease: IsolationLease
    private let journal: URL
    private var timebase = mach_timebase_info_data_t()
    public var onTopologyChange: (() -> Void)?

    public init(journal: URL = DrummFixPaths.recovery) throws {
        self.journal = journal
        lease = IsolationLease(journal: journal)
        mach_timebase_info(&timebase)
        try midiCheck(MIDIClientCreateWithBlock("DrummFix" as CFString, &client) { [weak self] notification in
            // Do not reconnect for our own property-change notifications.
            let kind = notification.pointee.messageID
            if kind == .msgObjectAdded || kind == .msgObjectRemoved || kind == .msgSetupChanged || kind == .msgIOError {
                DispatchQueue.main.async { [weak self] in self?.onTopologyChange?() }
            }
        }, "Создание MIDI-клиента")
        traces.reserveCapacity(256)
    }

    public var guardianAlive: Bool { lease.guardianAlive }

    public func start(source: MIDISourceInfo, helper: URL) throws {
        guard connectedSource == nil else { return }
        guard try restoreIsolation(journal: journal) else {
            throw RouteFailure("Подключи прежнее устройство Alesis, чтобы восстановить его MIDI-вход.")
        }
        do {
            try midiCheck(MIDISourceCreateWithProtocol(client, "DrummFix — Alesis Turbo" as CFString, ._1_0, &output), "Создание выхода")
            MIDIObjectSetStringProperty(output, kMIDIPropertyManufacturer, "DrummFix" as CFString)
            MIDIObjectSetStringProperty(output, kMIDIPropertyModel, "Alesis Turbo Hi-Hat Fix" as CFString)
            MIDIObjectSetStringProperty(output, kMIDIPropertyDisplayName, "DrummFix — Alesis Turbo" as CFString)
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "outputUID") != nil {
                _ = MIDIObjectSetIntegerProperty(output, kMIDIPropertyUniqueID, Int32(defaults.integer(forKey: "outputUID")))
            }
            if let id = midiInteger(output, kMIDIPropertyUniqueID) { defaults.set(Int(id), forKey: "outputUID") }
            try midiCheck(MIDIInputPortCreateWithProtocol(client, "Alesis Input" as CFString, ._1_0, &inputPort) { [weak self] list, _ in
                self?.receive(list)
            }, "Создание входа")
            try midiCheck(MIDIPortConnectSource(inputPort, source.endpoint, nil), "Подключение Alesis")
            connectedSource = source
            // Connect before hiding; other clients started afterwards only see our output.
            try lease.acquire(source, helper: helper)
            lock.lock()
            transformer = HiHatTransformer(dynamics: dynamics)
            traces.removeAll(keepingCapacity: true)
            traceID = 0; lastHit = nil; totalProcessing = 0; maxProcessing = 0; packetCount = 0
            error = nil; muted = false; running = true
            lock.unlock()
        } catch {
            try? stop()
            throw error
        }
    }

    public func stop() throws {
        lock.lock()
        running = false
        if output != 0 { _ = publishMIDI(output, timestamp: mach_absolute_time(), words: [0x20B97B00, 0x20B97800]) }
        lock.unlock()
        // Dispose after releasing the callback lock: CoreMIDI may wait for a callback.
        if inputPort != 0 { MIDIPortDispose(inputPort); inputPort = 0 }
        if output != 0 { MIDIEndpointDispose(output); output = 0 }
        connectedSource = nil
        try lease.release()
    }

    public func setMuted(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        muted = value
        if value, output != 0 { _ = publishMIDI(output, timestamp: mach_absolute_time(), words: [0x20B97B00, 0x20B97800]) }
    }

    public func clearLog() {
        lock.lock(); traces.removeAll(keepingCapacity: true); lock.unlock()
    }

    public func setDynamics(_ value: HiHatDynamics) {
        lock.lock(); defer { lock.unlock() }
        dynamics = value
        transformer.dynamics = value
    }

    public func audition(note: UInt8, velocity: UInt8 = 100) {
        lock.lock(); defer { lock.unlock() }
        guard running, !muted, velocity > 0, velocity <= 127,
              [UInt8(42), 44, 46].contains(note) else { return }
        _ = publishMIDI(output, timestamp: mach_absolute_time(), words: [0x20990000 | (UInt32(note) << 8) | UInt32(velocity), 0x20890000 | (UInt32(note) << 8)])
    }

    public func snapshot() -> EngineSnapshot {
        lock.lock(); defer { lock.unlock() }
        return EngineSnapshot(running: running, muted: muted, pedal: transformer.pedal,
                              correctedHits: transformer.correctedHits, totalHits: transformer.totalHits,
                              unknownHits: transformer.unknownHits, lastHit: lastHit, traces: traces,
                              meanProcessingMicroseconds: packetCount == 0 ? 0 : totalProcessing / Double(packetCount),
                              maxProcessingMicroseconds: maxProcessing, error: error)
    }

    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        let start = mach_absolute_time()
        lock.lock(); defer { lock.unlock() }
        guard running, output != 0 else { return }
        forEachMIDIPacket(list) { timestamp, packetWords in
            let words = Array(packetWords)
            let converted = transformer.transform(words)
            if !muted {
                let status = publishMIDI(output, timestamp: timestamp, words: converted)
                if status != noErr { error = "Ошибка передачи MIDI: \(status)" }
            }
            // Bounded diagnostic history. All formatting happens on the UI thread.
            var index = 0
            while index < words.count {
                let type = Int(words[index] >> 28)
                if type == 2 {
                    traceID += 1
                    let word = words[index]
                    if (word >> 20) & 0xF == 9, word & 0x7F != 0 { lastHit = Date() }
                    traces.append(MIDITrace(id: traceID, time: Date(), input: word, output: converted[index]))
                }
                index += HiHatTransformer.wordCounts[type]
            }
            if traces.count > 240 { traces.removeFirst(traces.count - 240) }
        }
        let elapsed = Double(mach_absolute_time() - start) * Double(timebase.numer) / Double(timebase.denom) / 1000
        packetCount += 1; totalProcessing += elapsed; maxProcessing = max(maxProcessing, elapsed)
    }

    deinit { try? stop(); if client != 0 { MIDIClientDispose(client) } }
}
