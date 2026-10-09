import SwiftUI
import AppKit
import DrummFixCore

@MainActor
final class AppModel: ObservableObject {
    @Published var sources: [MIDISourceInfo] = []
    @Published var selectedID: Int32 = 0
    @Published var running = false
    @Published var waiting = false
    @Published var garageBandRunning = false
    @Published var message = ""
    @Published var fatalMessage = ""
    @Published var snapshot: EngineSnapshot?
    @Published var showDiagnostics = false
    @Published var dynamics: HiHatDynamics = HiHatDynamics(rawValue: UserDefaults.standard.integer(forKey: "hihatDynamics")) ?? .original {
        didSet {
            engine?.setDynamics(dynamics)
            UserDefaults.standard.set(dynamics.rawValue, forKey: "hihatDynamics")
        }
    }
    private var sessionLock: SessionLock?
    private var engine: MIDIEngine?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var tick = 0
    private var reconnectID: Int32?
    private var sleeping = false
    private var transitioning = false

    var helperURL: URL {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("DrummFixGuard")
    }

    init() {
        do {
            sessionLock = try SessionLock()
            engine = try MIDIEngine()
            engine?.setDynamics(dynamics)
            if !(try restoreIsolation()) { message = "Подключи Alesis: нужно завершить восстановление прежнего подключения." }
            selectedID = Int32(UserDefaults.standard.integer(forKey: "selectedSource"))
            engine?.onTopologyChange = { [weak self] in self?.refresh() }
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.prepareForSleep() }
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleeping = false; self?.refresh() }
            })
        } catch { fatalMessage = error.localizedDescription }
    }

    func refresh() {
        garageBandRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.garageband10").isEmpty
        guard fatalMessage.isEmpty, !transitioning else { return }
        if !running { _ = try? restoreIsolation() }
        let connectedID = engine?.connectedSource?.id
        sources = hardwareSources().filter { !$0.isOffline && (!$0.isPrivate || $0.id == connectedID) }
        if !sources.contains(where: { $0.id == selectedID }), !running, !waiting {
            selectedID = sources.first(where: { $0.name.localizedCaseInsensitiveContains("Alesis Turbo") })?.id ?? sources.first?.id ?? 0
        }
        if running, let connected = engine?.connectedSource,
           findSource(id: connected.id).map({ $0.isOffline }) ?? true {
            reconnectID = connected.id
            disconnectForReconnect("USB отключён. Подключи Alesis снова; перед возобновлением закрой GarageBand.")
        }
    }

    func start() {
        refresh()
        guard !transitioning, fatalMessage.isEmpty, engine != nil else { return }
        guard !garageBandRunning else {
            message = "Сохрани проект и закрой GarageBand через ⌘Q. Затем включи исправление."
            return
        }
        guard let source = sources.first(where: { $0.id == selectedID }) else {
            message = "Подключи и включи Alesis Turbo по USB."
            return
        }
        transitioning = true
        defer { transitioning = false }
        do {
            try engine?.start(source: source, helper: helperURL)
            running = engine?.snapshot().running == true
            waiting = false; reconnectID = nil
            UserDefaults.standard.set(Int(selectedID), forKey: "selectedSource")
            message = "Исправление включено. Теперь открой GarageBand и выбери барабанный набор."
            snapshot = engine?.snapshot()
        } catch { message = error.localizedDescription; running = false; waiting = false }
    }

    func stop() {
        guard !transitioning else { return }
        transitioning = true
        defer { transitioning = false }
        waiting = false; reconnectID = nil
        do {
            try engine?.stop()
            message = garageBandRunning
                ? "Исправление выключено. Для прямого подключения барабанов перезапусти GarageBand."
                : "Исправление выключено. Обычный MIDI-вход Alesis восстановлен."
        } catch { message = error.localizedDescription }
        running = false; snapshot = engine?.snapshot(); refresh()
    }

    private func disconnectForReconnect(_ explanation: String) {
        transitioning = true
        defer { transitioning = false }
        do { try engine?.stop() } catch { message = error.localizedDescription }
        running = false; waiting = true; message = explanation
    }

    private func prepareForSleep() {
        sleeping = true
        if running {
            reconnectID = selectedID
            disconnectForReconnect("Mac был в режиме сна. Закрой GarageBand — подключение восстановится автоматически.")
        }
    }

    private func poll() {
        snapshot = engine?.snapshot()
        tick += 1
        if tick % 10 == 0 {
            refresh()
            if running, engine?.guardianAlive != true {
                stop()
                message = "Процесс восстановления остановился. MIDI-вход восстановлен; включи исправление заново."
            }
            if let error = snapshot?.error, running { stop(); message = error }
            if waiting, !sleeping, !garageBandRunning,
               let id = reconnectID, sources.contains(where: { $0.id == id }) {
                selectedID = id; start()
            }
        }
    }

    func toggleSilence() { engine?.setMuted(!(snapshot?.muted ?? false)); snapshot = engine?.snapshot() }
    func audition(_ note: UInt8, velocity: UInt8 = 100) { engine?.audition(note: note, velocity: velocity) }
    func clearLog() { engine?.clearLog(); snapshot = engine?.snapshot() }

    func openGarageBand() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.garageband10") else {
            message = "GarageBand не найден в папке Applications."; return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func saveDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "DrummFix-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url, let state = engine?.snapshot() else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let header = "DrummFix 0.2.1\nDevice: \(sources.first(where: { $0.id == selectedID })?.name ?? "disconnected")\nRunning: \(state.running)\nOutput muted: \(state.muted)\nHi-hat dynamics: \(dynamics.title)\nCorrected hits: \(state.correctedHits)\nProcessing callback mean/max (µs, not audio latency): \(state.meanProcessingMicroseconds) / \(state.maxProcessingMicroseconds)\n\n"
        let rows = state.traces.map {
            "\(formatter.string(from: $0.time))\t\($0.description)\t" + String(format: "%08X → %08X", $0.input, $0.output)
        }.joined(separator: "\n")
        do { try (header + rows).write(to: url, atomically: true, encoding: .utf8) }
        catch { message = "Не удалось сохранить журнал: \(error.localizedDescription)" }
    }

    func shutdown() {
        timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        try? engine?.stop()
        engine = nil
        sessionLock = nil
    }
}
