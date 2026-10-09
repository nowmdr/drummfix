import Foundation
import CoreMIDI

public struct MIDIError: LocalizedError {
    public let operation: String
    public let status: OSStatus
    public var errorDescription: String? { "\(operation): CoreMIDI \(status)" }
    public init(_ operation: String, _ status: OSStatus) { self.operation = operation; self.status = status }
}

public func midiCheck(_ status: OSStatus, _ operation: String) throws {
    if status != noErr { throw MIDIError(operation, status) }
}

public func midiString(_ object: MIDIObjectRef, _ key: CFString) -> String {
    var value: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(object, key, &value) == noErr else { return "" }
    return value?.takeRetainedValue() as String? ?? ""
}

public func midiInteger(_ object: MIDIObjectRef, _ key: CFString) -> Int32? {
    var value: Int32 = 0
    return MIDIObjectGetIntegerProperty(object, key, &value) == noErr ? value : nil
}

public struct MIDISourceInfo: Identifiable, Equatable, Codable {
    public let endpoint: MIDIEndpointRef
    public let id: Int32
    public let name: String
    public let isPrivate: Bool
    public let isOffline: Bool
    public let isHardware: Bool

    public init(_ endpoint: MIDIEndpointRef, hardware: Bool = false) {
        self.endpoint = endpoint
        id = midiInteger(endpoint, kMIDIPropertyUniqueID) ?? Int32(bitPattern: endpoint)
        let display = midiString(endpoint, kMIDIPropertyDisplayName)
        name = display.isEmpty ? midiString(endpoint, kMIDIPropertyName) : display
        isPrivate = midiInteger(endpoint, kMIDIPropertyPrivate) == 1
        isOffline = midiInteger(endpoint, kMIDIPropertyOffline) == 1
        var entity: MIDIEntityRef = 0
        MIDIEndpointGetEntity(endpoint, &entity)
        isHardware = hardware || entity != 0
    }
}

public func visibleSources() -> [MIDISourceInfo] {
    (0..<MIDIGetNumberOfSources()).map { MIDISourceInfo(MIDIGetSource($0)) }
}

/// Walking the device tree also finds hardware endpoints hidden after a crashed session.
public func hardwareSources() -> [MIDISourceInfo] {
    var result: [MIDISourceInfo] = []
    for deviceIndex in 0..<MIDIGetNumberOfDevices() {
        let device = MIDIGetDevice(deviceIndex)
        for entityIndex in 0..<MIDIDeviceGetNumberOfEntities(device) {
            let entity = MIDIDeviceGetEntity(device, entityIndex)
            for sourceIndex in 0..<MIDIEntityGetNumberOfSources(entity) {
                result.append(MIDISourceInfo(MIDIEntityGetSource(entity, sourceIndex), hardware: true))
            }
        }
    }
    return result
}

public func findSource(id: Int32) -> MIDISourceInfo? {
    var object: MIDIObjectRef = 0
    var type: MIDIObjectType = .other
    if MIDIObjectFindByUniqueID(id, &object, &type) == noErr, type == .source {
        return MIDISourceInfo(object)
    }
    return hardwareSources().first { $0.id == id } ?? visibleSources().first { $0.id == id }
}

/// The packet pointer must be derived from the original list, not a copied tuple.
public func forEachMIDIPacket(_ list: UnsafePointer<MIDIEventList>, _ body: (UInt64, UnsafeBufferPointer<UInt32>) -> Void) {
    let packetOffset = MemoryLayout<MIDIEventList>.offset(of: \.packet)!
    let wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \.words)!
    var packet = UnsafeRawPointer(list).advanced(by: packetOffset).assumingMemoryBound(to: MIDIEventPacket.self)
    for _ in 0..<list.pointee.numPackets {
        let words = UnsafeRawPointer(packet).advanced(by: wordsOffset).assumingMemoryBound(to: UInt32.self)
        body(packet.pointee.timeStamp, UnsafeBufferPointer(start: words, count: Int(packet.pointee.wordCount)))
        packet = UnsafePointer(MIDIEventPacketNext(packet))
    }
}

@discardableResult
public func publishMIDI(_ source: MIDIEndpointRef, timestamp: UInt64, words: [UInt32]) -> OSStatus {
    guard !words.isEmpty else { return noErr }
    let size = max(1024, words.count * 4 + 64)
    let storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
    defer { storage.deallocate() }
    let list = storage.assumingMemoryBound(to: MIDIEventList.self)
    let first = MIDIEventListInit(list, ._1_0)
    words.withUnsafeBufferPointer {
        _ = MIDIEventListAdd(list, size, first, timestamp == 0 ? mach_absolute_time() : timestamp, $0.count, $0.baseAddress!)
    }
    return MIDIReceivedEventList(source, list)
}
