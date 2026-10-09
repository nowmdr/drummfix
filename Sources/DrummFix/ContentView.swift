import SwiftUI
import DrummFixCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    private var muted: Bool { model.snapshot?.muted ?? false }
    private var accent: Color { muted ? .orange : model.running ? .green : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.teal)
                    .frame(width: 52, height: 52)
                    .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("DrummFix").font(.title2.bold())
                    Text("Alesis Turbo · GarageBand").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(muted ? "Тишина" : model.running ? "Работает" : model.waiting ? "Ожидание" : "Выключен")
                        .font(.caption.weight(.medium))
                }.padding(.horizontal, 10).padding(.vertical, 6)
                    .background(accent.opacity(0.1), in: Capsule())
            }

            if !model.fatalMessage.isEmpty {
                Label(model.fatalMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("БАРАБАНЫ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        Picker("Устройство", selection: $model.selectedID) {
                            if model.sources.isEmpty { Text("Подключи Alesis по USB").tag(Int32(0)) }
                            ForEach(model.sources) { Text($0.name).tag($0.id) }
                        }.labelsHidden().disabled(model.running || model.waiting)
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .help("Обновить устройства")
                    }
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Хай-хэт").font(.subheadline).foregroundStyle(.secondary)
                        Text(model.running ? (model.snapshot?.pedal.rawValue ?? "Ещё нет данных") : "—")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                        Text("Последнее полученное состояние")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Исправлено ударов").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(model.snapshot?.correctedHits ?? 0)")
                            .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                        HStack(spacing: 5) {
                            Circle().fill(hitIsRecent ? Color.teal : Color.secondary.opacity(0.25)).frame(width: 6, height: 6)
                            Text("Всего: \(model.snapshot?.totalHits ?? 0)")
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(16).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    Text("Динамика закрытого хай-хэта")
                    Spacer()
                    Picker("Динамика закрытого хай-хэта", selection: $model.dynamics) {
                        ForEach(HiHatDynamics.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }.labelsHidden().frame(width: 155)
                }.font(.subheadline)

                VStack(alignment: .leading, spacing: 10) {
                    if !model.running, !model.waiting {
                        Text(model.garageBandRunning
                             ? "Сначала сохрани проект и закрой GarageBand через ⌘Q."
                             : "Включи исправление, затем открой GarageBand.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Button(model.running ? "Выключить" : model.waiting ? "Отменить ожидание" : "Включить исправление") {
                            if model.running || model.waiting { model.stop() } else { model.start() }
                        }
                        .buttonStyle(.borderedProminent).tint(.teal).controlSize(.large)
                        .disabled(!model.running && !model.waiting && (model.sources.isEmpty || model.garageBandRunning))
                        if model.running {
                            Button("Открыть GarageBand") { model.openGarageBand() }
                                .controlSize(.large)
                        }
                    }
                    if !model.message.isEmpty {
                        Text(model.message).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()
                DisclosureGroup("Диагностика и проверка", isExpanded: $model.showDiagnostics) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button(muted ? "Вернуть звук" : "Проверка тишины") { model.toggleSilence() }
                                .disabled(!model.running)
                            Text("При включённой проверке удары должны быть неслышны.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Звуки:").font(.caption).foregroundStyle(.secondary)
                            Button("Открытый") { model.audition(46) }
                            Button("Закрытый") { model.audition(42) }
                            Button("Педаль") { model.audition(44) }
                        }.disabled(!model.running || muted)
                        HStack {
                            Text("Сравнить закрытый:").font(.caption).foregroundStyle(.secondary)
                            Button("Тихо (20)") { model.audition(42, velocity: 20) }
                            Button("Сильно (110)") { model.audition(42, velocity: 110) }
                        }.disabled(!model.running || muted)
                        if let state = model.snapshot {
                            Text(String(format: "Обработка MIDI: средняя %.3f мс · максимум %.3f мс", state.meanProcessingMicroseconds / 1000, state.maxProcessingMicroseconds / 1000))
                                .font(.caption2).foregroundStyle(.secondary)
                            Text("Это время обработки событий, без задержки звука GarageBand.")
                                .font(.caption2).foregroundStyle(.secondary)
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 3) {
                                    ForEach(state.traces.suffix(24).reversed()) { event in
                                        Text(event.description).font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(event.input == event.output ? Color.secondary : Color.teal)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(height: 120).padding(8).background(.background, in: RoundedRectangle(cornerRadius: 6))
                        }
                        HStack {
                            Button("Сохранить журнал…") { model.saveDiagnostics() }
                            Button("Очистить") { model.clearLog() }
                            Spacer()
                            Text("0.2.1").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }.padding(.top, 12)
                }.font(.subheadline)
            }
        }
        .padding(24)
        .frame(width: 530)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hitIsRecent: Bool {
        guard let last = model.snapshot?.lastHit, model.running else { return false }
        return Date().timeIntervalSince(last) < 0.15
    }
}
