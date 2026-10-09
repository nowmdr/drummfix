import Foundation
import CoreMIDI
import DrummFixCore

var client: MIDIClientRef = 0
guard MIDIClientCreateWithBlock("DrummFix Recovery" as CFString, &client, nil) == noErr else { exit(2) }
let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--is-visible", let id = Int32(arguments[2]) {
    let visible = visibleSources().contains { $0.id == id }
    MIDIClientDispose(client)
    exit(visible ? 0 : 1)
}
guard arguments.count == 3, arguments[1] == "--watch" else { MIDIClientDispose(client); exit(2) }
let journal = URL(fileURLWithPath: arguments[2])
let expected = try? Data(contentsOf: journal)
FileHandle.standardOutput.write(Data("READY\n".utf8))
_ = FileHandle.standardInput.readDataToEndOfFile()
do {
    // Use the same session lock as the app. A newly launched app may have already
    // recovered and opened another route; the old helper must not touch that route.
    // If the parent is still alive, normal release has already restored the source.
    // If it died, the OS has released the flock. Retry briefly during process teardown.
    var lock: SessionLock?
    for _ in 0..<20 {
        lock = try? SessionLock(directory: journal.deletingLastPathComponent())
        if lock != nil { break }
        usleep(50_000)
    }
    if lock != nil, let expected, (try? Data(contentsOf: journal)) == expected {
        _ = try restoreIsolation(journal: journal)
    }
    withExtendedLifetime(lock) {}
    MIDIClientDispose(client)
    exit(0)
} catch {
    // Keep the journal for recovery on the next app launch.
    MIDIClientDispose(client)
    exit(3)
}
