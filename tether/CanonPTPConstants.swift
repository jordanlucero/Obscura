import Foundation

// MARK: - Data Helpers

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func readLittleEndian<T: FixedWidthInteger>(at offset: Int) -> T {
        T(littleEndian: self.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) })
    }
}

// MARK: - Connection State

enum ConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case error
}

// MARK: - Errors

enum CameraError: Error, LocalizedError, Sendable {
    case notConnected
    case invalidResponse
    case ptpError(UInt16)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected: "Camera not connected"
        case .invalidResponse: "Invalid response from camera"
        case .ptpError(let code): "PTP error: 0x\(String(code, radix: 16, uppercase: true))"
        case .timeout: "Command timed out"
        }
    }
}

// MARK: - Canon PTP Operation Codes

enum CanonPTPOperation: UInt16, Sendable {
    case setDevicePropValueEx = 0x9110
    case setRemoteMode        = 0x9114
    case setEventMode         = 0x9115
    case getEvent             = 0x9116
    case remoteReleaseOn      = 0x9128
    case remoteReleaseOff     = 0x9129
    case getViewFinderData    = 0x9153
}

// MARK: - Canon Property Codes

enum CanonProperty: UInt32, Sendable {
    case shutterSpeed    = 0xD102
    case iso             = 0xD103
    case evfOutputDevice = 0xD1B0
    case evfMode         = 0xD1B4
}

// MARK: - PTP Response Codes

enum PTPResponseCode {
    static let ok: UInt16 = 0x2001
}

// MARK: - ISO Values

struct ISOValue: Identifiable, Hashable, Sendable {
    let name: String
    let code: UInt32
    var id: UInt32 { code }

    static let all: [ISOValue] = [
        ISOValue(name: "100",   code: 0x48),
        ISOValue(name: "125",   code: 0x4B),
        ISOValue(name: "160",   code: 0x4D),
        ISOValue(name: "200",   code: 0x50),
        ISOValue(name: "250",   code: 0x53),
        ISOValue(name: "320",   code: 0x55),
        ISOValue(name: "400",   code: 0x58),
        ISOValue(name: "500",   code: 0x5B),
        ISOValue(name: "640",   code: 0x5D),
        ISOValue(name: "800",   code: 0x60),
        ISOValue(name: "1000",  code: 0x63),
        ISOValue(name: "1250",  code: 0x65),
        ISOValue(name: "1600",  code: 0x68),
        ISOValue(name: "2000",  code: 0x6B),
        ISOValue(name: "2500",  code: 0x6D),
        ISOValue(name: "3200",  code: 0x70),
        ISOValue(name: "4000",  code: 0x73),
        ISOValue(name: "5000",  code: 0x75),
        ISOValue(name: "6400",  code: 0x78),
        ISOValue(name: "8000",  code: 0x7B),
        ISOValue(name: "10000", code: 0x7D),
        ISOValue(name: "12800", code: 0x80),
        ISOValue(name: "16000", code: 0x83),
        ISOValue(name: "20000", code: 0x85),
        ISOValue(name: "25600", code: 0x88),
    ]

    static func name(for code: UInt32) -> String {
        all.first { $0.code == code }?.name ?? "---"
    }
}

// MARK: - Shutter Speed Values

struct ShutterSpeedValue: Identifiable, Hashable, Sendable {
    let name: String
    let code: UInt32
    var id: UInt32 { code }

    static let all: [ShutterSpeedValue] = [
        // Long exposures
        ShutterSpeedValue(name: "30\"",   code: 0x10),
        ShutterSpeedValue(name: "25\"",   code: 0x13),
        ShutterSpeedValue(name: "20\"",   code: 0x15),
        ShutterSpeedValue(name: "15\"",   code: 0x18),
        ShutterSpeedValue(name: "13\"",   code: 0x1B),
        ShutterSpeedValue(name: "10\"",   code: 0x1D),
        ShutterSpeedValue(name: "8\"",    code: 0x20),
        ShutterSpeedValue(name: "6\"",    code: 0x23),
        ShutterSpeedValue(name: "5\"",    code: 0x25),
        ShutterSpeedValue(name: "4\"",    code: 0x28),
        ShutterSpeedValue(name: "3.2\"",  code: 0x2B),
        ShutterSpeedValue(name: "2.5\"",  code: 0x2D),
        ShutterSpeedValue(name: "2\"",    code: 0x30),
        ShutterSpeedValue(name: "1.6\"",  code: 0x33),
        ShutterSpeedValue(name: "1.3\"",  code: 0x35),
        ShutterSpeedValue(name: "1\"",    code: 0x38),
        ShutterSpeedValue(name: "0.8\"",  code: 0x3B),
        ShutterSpeedValue(name: "0.6\"",  code: 0x3D),
        // Fractions
        ShutterSpeedValue(name: "1/2",    code: 0x40),
        ShutterSpeedValue(name: "1/2.5",  code: 0x43),
        ShutterSpeedValue(name: "1/3",    code: 0x45),
        ShutterSpeedValue(name: "1/4",    code: 0x48),
        ShutterSpeedValue(name: "1/5",    code: 0x4B),
        ShutterSpeedValue(name: "1/6",    code: 0x4D),
        ShutterSpeedValue(name: "1/8",    code: 0x50),
        ShutterSpeedValue(name: "1/10",   code: 0x53),
        ShutterSpeedValue(name: "1/13",   code: 0x55),
        ShutterSpeedValue(name: "1/15",   code: 0x58),
        ShutterSpeedValue(name: "1/20",   code: 0x5B),
        ShutterSpeedValue(name: "1/25",   code: 0x5D),
        ShutterSpeedValue(name: "1/30",   code: 0x60),
        ShutterSpeedValue(name: "1/40",   code: 0x63),
        ShutterSpeedValue(name: "1/50",   code: 0x65),
        ShutterSpeedValue(name: "1/60",   code: 0x68),
        ShutterSpeedValue(name: "1/80",   code: 0x6B),
        ShutterSpeedValue(name: "1/100",  code: 0x6D),
        ShutterSpeedValue(name: "1/125",  code: 0x70),
        ShutterSpeedValue(name: "1/160",  code: 0x73),
        ShutterSpeedValue(name: "1/200",  code: 0x75),
        ShutterSpeedValue(name: "1/250",  code: 0x78),
        ShutterSpeedValue(name: "1/320",  code: 0x7B),
        ShutterSpeedValue(name: "1/400",  code: 0x7D),
        ShutterSpeedValue(name: "1/500",  code: 0x80),
        ShutterSpeedValue(name: "1/640",  code: 0x83),
        ShutterSpeedValue(name: "1/800",  code: 0x85),
        ShutterSpeedValue(name: "1/1000", code: 0x88),
        ShutterSpeedValue(name: "1/1250", code: 0x8B),
        ShutterSpeedValue(name: "1/1600", code: 0x8D),
        ShutterSpeedValue(name: "1/2000", code: 0x90),
        ShutterSpeedValue(name: "1/2500", code: 0x93),
        ShutterSpeedValue(name: "1/3200", code: 0x95),
        ShutterSpeedValue(name: "1/4000", code: 0x98),
        ShutterSpeedValue(name: "1/5000", code: 0x9B),
        ShutterSpeedValue(name: "1/6400", code: 0x9D),
        ShutterSpeedValue(name: "1/8000", code: 0xA0),
    ]

    static func name(for code: UInt32) -> String {
        all.first { $0.code == code }?.name ?? "---"
    }
}
