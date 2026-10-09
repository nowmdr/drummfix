import Foundation
import CoreMIDI
import Darwin

public enum DrummFixPaths {
    public static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DrummFix", isDirectory: true)
    }
    public static var recovery: URL { support.appendingPathComponent("recovery.json") }
}

public struct RecoveryRecord: Codable {
    public var session = UUID()
    public let id: Int32
    public let name: String
    public let previousPrivate: Int32?
}

public struct RouteFailure: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Held only by the main process. FD_CLOEXEC prevents the helper retaining the lock.
public final class SessionLock {
    private let descriptor: Int32
    public init(directory: URL = DrummFixPaths.support) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        descriptor = open(directory.appendingPathComponent("session.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw RouteFailure("Не удалось открыть файл сессии DrummFix.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw RouteFailure("DrummFix уже запущен. Открой существующее окно приложения.")
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

/// Restores only the endpoint whose ID was saved before DrummFix changed its property.
/// A missing device keeps its journal, so reconnect/relaunch can finish recovery.
@discardableResult
public func restoreIsolation(journal: URL = DrummFixPaths.recovery) throws -> Bool {
    guard FileManager.default.fileExists(atPath: journal.path) else { return true }
    let record = try JSONDecoder().decode(RecoveryRecord.self, from: Data(contentsOf: journal))
    guard let source = findSource(id: record.id) else { return false }
    let status: OSStatus
    if let previous = record.previousPrivate {
        status = MIDIObjectSetIntegerProperty(source.endpoint, kMIDIPropertyPrivate, previous)
    } else {
        status = midiInteger(source.endpoint, kMIDIPropertyPrivate) == nil
            ? noErr : MIDIObjectRemoveProperty(source.endpoint, kMIDIPropertyPrivate)
    }
    try midiCheck(status, "Восстановление MIDI-входа")
    guard midiInteger(source.endpoint, kMIDIPropertyPrivate) != 1 else {
        throw RouteFailure("MIDI-вход ещё скрыт. Перезапусти DrummFix для восстановления.")
    }
    try FileManager.default.removeItem(at: journal)
    return true
}

public final class IsolationLease {
    private let journal: URL
    private var guardian: Process?
    private var lifeline: Pipe?
    public private(set) var source: MIDISourceInfo?

    public init(journal: URL = DrummFixPaths.recovery) { self.journal = journal }

    public func acquire(_ source: MIDISourceInfo, helper: URL) throws {
        guard self.source == nil else { throw RouteFailure("Маршрут уже включён.") }
        guard !source.isPrivate, !source.isOffline else { throw RouteFailure("MIDI-вход занят другим приложением или отключён.") }
        guard !FileManager.default.fileExists(atPath: journal.path) else {
            throw RouteFailure("Сначала нужно восстановить предыдущий MIDI-маршрут.")
        }
        let record = RecoveryRecord(id: source.id, name: source.name, previousPrivate: midiInteger(source.endpoint, kMIDIPropertyPrivate))
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: journal, options: .atomic)
        self.source = source
        do {
            let process = Process()
            let pipe = Pipe()
            let ready = Pipe()
            process.executableURL = helper
            process.arguments = ["--watch", journal.path]
            process.standardInput = pipe
            process.standardOutput = ready
            process.standardError = FileHandle.nullDevice
            try process.run()
            // Parent owns only the write end. EOF reaches the guardian even after SIGKILL.
            pipe.fileHandleForReading.closeFile()
            ready.fileHandleForWriting.closeFile()
            guardian = process
            lifeline = pipe
            var descriptor = pollfd(fd: ready.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let available = poll(&descriptor, 1, 3000)
            guard available > 0,
                  String(data: ready.fileHandleForReading.readData(ofLength: 6), encoding: .utf8) == "READY\n" else {
                throw RouteFailure("Защита восстановления не запустилась. MIDI-вход не изменён.")
            }
            ready.fileHandleForReading.closeFile()
            try midiCheck(MIDIObjectSetIntegerProperty(source.endpoint, kMIDIPropertyPrivate, 1), "Изоляция исходного MIDI-входа")
            guard midiInteger(source.endpoint, kMIDIPropertyPrivate) == 1 else { throw RouteFailure("Не удалось изолировать MIDI-вход.") }

            let verifier = Process()
            verifier.executableURL = helper
            verifier.arguments = ["--is-visible", String(source.id)]
            verifier.standardOutput = FileHandle.nullDevice
            verifier.standardError = FileHandle.nullDevice
            try verifier.run()
            verifier.waitUntilExit()
            guard verifier.terminationStatus == 1 else {
                throw RouteFailure("Другие приложения всё ещё видят исходный MIDI-вход. Исправление не включено.")
            }
        } catch {
            try? release()
            throw error
        }
    }

    public var guardianAlive: Bool { guardian?.isRunning == true }

    public func release() throws {
        var restoreError: Error?
        do { _ = try restoreIsolation(journal: journal) } catch { restoreError = error }
        lifeline?.fileHandleForWriting.closeFile()
        lifeline = nil
        // Normally the helper only sees an already-removed journal and exits immediately.
        // Never kill it: its remaining job may be restoring a disconnected endpoint.
        guardian = nil
        source = nil
        if let error = restoreError { throw error }
    }

    deinit { try? release() }
}
