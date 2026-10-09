import Foundation

public enum PedalState: String, Equatable {
    case unknown = "Ещё нет данных"
    case open = "Открыт"
    case closed = "Закрыт"
}

public enum HiHatDynamics: Int, CaseIterable, Identifiable {
    case original = 0
    case moderate = 1
    case strong = 2

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .original: return "Исходная"
        case .moderate: return "Умеренная"
        case .strong: return "Сильная"
        }
    }

    private static let curves: [[UInt8]] = [1.0, 0.65, 0.45].map { exponent in
        (0...127).map { value in
            guard value > 0 else { return 0 }
            return UInt8(max(1, min(127, Int((pow(Double(value) / 127, exponent) * 127).rounded()))))
        }
    }

    public func adjusted(_ velocity: UInt8) -> UInt8 { Self.curves[rawValue][Int(velocity)] }
}

public struct MIDITrace: Identifiable {
    public let id: UInt64
    public let time: Date
    public let input: UInt32
    public let output: UInt32
    public var description: String {
        let status = (input >> 16) & 0xFF
        let note = (input >> 8) & 0x7F
        let value = input & 0x7F
        let outputNote = (output >> 8) & 0x7F
        let outputValue = output & 0x7F
        let channel = (status & 0xF) + 1
        switch status & 0xF0 {
        case 0xB0: return "CH\(channel)  CC\(note) = \(value)"
        case 0x90 where value > 0:
            return "CH\(channel)  удар \(note)\(note == outputNote ? "" : " → \(outputNote)")  сила \(value)\(value == outputValue ? "" : " → \(outputValue)")"
        case 0x80, 0x90: return "CH\(channel)  конец \(note)\(note == outputNote ? "" : " → \(outputNote)")"
        case 0xA0: return "CH\(channel)  Aftertouch \(note) = \(value)"
        default: return String(format: "%08X → %08X", input, output)
        }
    }
}

/// Stateful conversion of MIDI 1.0 channel-voice UMP messages. The caller serializes access.
public struct HiHatTransformer {
    public private(set) var pedal: PedalState = .unknown
    public private(set) var correctedHits = 0
    public private(set) var totalHits = 0
    public private(set) var unknownHits = 0
    private var states = [PedalState](repeating: .unknown, count: 256)
    private var outstanding = [[UInt8]](repeating: [], count: 256)
    public let channel: UInt8
    public var dynamics: HiHatDynamics
    public init(channel: UInt8 = 9, dynamics: HiHatDynamics = .original) {
        self.channel = channel
        self.dynamics = dynamics
    }

    // UMP lengths include reserved types, so SysEx payload words cannot become notes.
    public static let wordCounts = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

    public mutating func transform(_ words: [UInt32]) -> [UInt32] {
        var result = words
        var index = 0
        while index < result.count {
            let type = Int(result[index] >> 28)
            let length = Self.wordCounts[type]
            guard index + length <= result.count else { break }
            if type == 2 { result[index] = transformVoice(result[index]) }
            index += length
        }
        return result
    }

    private mutating func transformVoice(_ word: UInt32) -> UInt32 {
        let status = UInt8((word >> 16) & 0xFF)
        let messageChannel = status & 0xF
        guard messageChannel == channel else { return word }
        let group = Int((word >> 24) & 0xF)
        let slot = group * 16 + Int(messageChannel)
        let type = status & 0xF0
        let note = UInt8((word >> 8) & 0x7F)
        let velocity = UInt8(word & 0x7F)
        if type == 0xB0, note == 4 {
            // The measured Turbo pedal only emits 0 and 127; never guess an unmeasured state.
            states[slot] = velocity == 0 ? .open : velocity == 127 ? .closed : .unknown
            pedal = states[slot]
        }
        if type == 0xB0, [UInt8(120), 121, 123].contains(note) {
            outstanding[slot].removeAll(keepingCapacity: true)
            if note == 121 { states[slot] = .unknown; pedal = .unknown }
        }
        if type == 0x90, velocity > 0 {
            totalHits += 1
            if note == 44 { states[slot] = .closed; pedal = .closed }
        }
        guard note == 46 else { return word }
        if type == 0x90, velocity > 0 {
            let output: UInt8 = states[slot] == .closed ? 42 : 46
            if output == 42 { correctedHits += 1 }
            if states[slot] == .unknown { unknownHits += 1 }
            // A broken source cannot grow this queue indefinitely.
            if outstanding[slot].count >= 128 { outstanding[slot].removeFirst() }
            outstanding[slot].append(output)
            let mapped = output == 42 ? dynamics.adjusted(velocity) : velocity
            return (word & 0xFFFF0000) | (UInt32(output) << 8) | UInt32(mapped)
        }
        if type == 0x80 || (type == 0x90 && velocity == 0) {
            let output = outstanding[slot].isEmpty ? 46 : outstanding[slot].removeFirst()
            return (word & 0xFFFF00FF) | (UInt32(output) << 8)
        }
        // Preserve pedal aftertouch, CC, and every other articulation unchanged.
        return word
    }
}
