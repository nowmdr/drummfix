import Foundation
import DrummFixCore

// No XCTest dependency: also runs with standalone Apple Command Line Tools.
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    guard actual == expected else { fatalError("Expected \(expected), got \(actual)", file: file, line: line) }
}

@main
struct HiHatTests {
    static func main() {
        testActualOpenAndClosedCapture()
        testNoteOffKeepsOriginalMappingWhenPedalChanges()
        testZeroVelocityAndRepeatedHits()
        testOtherChannelsPadsAndSysexAreUntouched()
        testUnknownStartupAndResetDoNotAssumeClosed()
        testGroupsAreIndependentAndUnmeasuredCCIsUnknown()
        testClosedHiHatDynamicsPreservesOrderAndOtherNotes()
        print("PASS: 7 MIDI transformation scenarios")
    }
    static func testActualOpenAndClosedCapture() {
        var converter = HiHatTransformer()
        let input: [UInt32] = [0x20B90400, 0x20992E2E, 0x20892E00,
                              0x20992C64, 0x20892C00, 0x20A92E7F, 0x20A9157F,
                              0x20B9047F, 0x20992E34, 0x20892E00,
                              0x20B9047F, 0x20992E3E, 0x20892E00,
                              0x20B90400, 0x20992E3C, 0x20892E00]
        var expected = input
        for index in [8, 9, 11, 12] { expected[index] = (expected[index] & 0xFFFF00FF) | 0x2A00 }
        XCTAssertEqual(converter.transform(input), expected)
        XCTAssertEqual(converter.correctedHits, 2)
        XCTAssertEqual(converter.pedal, .open)
    }

    static func testNoteOffKeepsOriginalMappingWhenPedalChanges() {
        var converter = HiHatTransformer()
        XCTAssertEqual(converter.transform([0x20B9047F, 0x20992E7F, 0x20B90400, 0x20892E22]),
                       [0x20B9047F, 0x20992A7F, 0x20B90400, 0x20892A22])
    }

    static func testZeroVelocityAndRepeatedHits() {
        var converter = HiHatTransformer()
        _ = converter.transform([0x20B9047F])
        for velocity: UInt32 in [1, 32, 64, 127] {
            XCTAssertEqual(converter.transform([0x20992E00 | velocity, 0x20992E00]),
                           [0x20992A00 | velocity, 0x20992A00])
        }
        XCTAssertEqual(converter.correctedHits, 4)
    }

    static func testOtherChannelsPadsAndSysexAreUntouched() {
        var converter = HiHatTransformer()
        _ = converter.transform([0x20B9047F])
        let input: [UInt32] = [0x2098267F, 0x20992C64, 0x20A92E7F, 0x20992644,
                              0x30130000, 0x20992E7F, // SysEx payload resembles note-on
                              0x40992E7F, 0xFFFFFFFF] // MIDI 2.0 (not requested from CoreMIDI)
        XCTAssertEqual(converter.transform(input), input)
    }

    static func testUnknownStartupAndResetDoNotAssumeClosed() {
        var converter = HiHatTransformer()
        XCTAssertEqual(converter.transform([0x20992E50, 0x20892E00]), [0x20992E50, 0x20892E00])
        XCTAssertEqual(converter.unknownHits, 1)
        _ = converter.transform([0x20B9047F, 0x20B97900])
        XCTAssertEqual(converter.pedal, .unknown)
        XCTAssertEqual(converter.transform([0x20992E50]), [0x20992E50])
    }

    static func testGroupsAreIndependentAndUnmeasuredCCIsUnknown() {
        var converter = HiHatTransformer()
        XCTAssertEqual(converter.transform([0x20B9047F, 0x21992E7F]), [0x20B9047F, 0x21992E7F])
        _ = converter.transform([0x20B90440])
        XCTAssertEqual(converter.pedal, .unknown)
        XCTAssertEqual(converter.transform([0x20992E7F]), [0x20992E7F])
    }

    static func testClosedHiHatDynamicsPreservesOrderAndOtherNotes() {
        for mode in HiHatDynamics.allCases {
            XCTAssertEqual(mode.adjusted(0), 0)
            XCTAssertEqual(mode.adjusted(127), 127)
            var previous: UInt8 = 0
            for velocity in UInt8(1)...UInt8(127) {
                let mapped = mode.adjusted(velocity)
                assert(mapped >= previous)
                previous = mapped
            }
        }
        var converter = HiHatTransformer(dynamics: .moderate)
        XCTAssertEqual(converter.transform([0x20B9047F, 0x20992E14, 0x20892E00,
                                            0x20992640, 0x20B90400, 0x20992E14, 0x20892E00]),
                       [0x20B9047F, 0x20992A00 | UInt32(HiHatDynamics.moderate.adjusted(20)), 0x20892A00,
                        0x20992640, 0x20B90400, 0x20992E14, 0x20892E00])
        converter.dynamics = .strong
        XCTAssertEqual(converter.transform([0x20B9047F, 0x20992E14, 0x20892E00]),
                       [0x20B9047F, 0x20992A00 | UInt32(HiHatDynamics.strong.adjusted(20)), 0x20892A00])
        assert(HiHatDynamics.strong.adjusted(20) > HiHatDynamics.moderate.adjusted(20))
    }
}
