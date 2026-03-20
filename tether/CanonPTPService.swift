@preconcurrency import ImageCaptureCore
import Foundation

/// Thread-safe flag ensuring a continuation is resumed exactly once.
private final class OnceFlag: @unchecked Sendable {
    private var fired = false
    private let lock = NSLock()

    func tryFire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return false }
        fired = true
        return true
    }
}

class CanonPTPService {
    private let device: ICCameraDevice
    private var transactionID: UInt32 = 0

    init(device: ICCameraDevice) {
        self.device = device
    }

    // MARK: - PTP Command Building

    private func buildPTPCommand(operation: CanonPTPOperation, parameters: [UInt32] = []) -> Data {
        let headerSize = 12 // length(4) + type(2) + code(2) + transactionID(4)
        let totalSize = headerSize + parameters.count * 4

        var data = Data(capacity: totalSize)
        data.appendLittleEndian(UInt32(totalSize))
        data.appendLittleEndian(UInt16(0x0001)) // Command block type
        data.appendLittleEndian(operation.rawValue)
        transactionID += 1
        data.appendLittleEndian(transactionID)

        for param in parameters {
            data.appendLittleEndian(param)
        }

        return data
    }

    private func hexDump(_ data: Data, max: Int = 48) -> String {
        data.prefix(max).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // MARK: - Send Command

    /// Sends a PTP command and returns the data-in payload.
    ///
    /// `requestSendPTPCommand` completion handler returns:
    /// - First param: data-in phase payload (empty for commands without data-in)
    /// - Second param: PTP response container (12+ bytes)
    func sendCommand(
        operation: CanonPTPOperation,
        parameters: [UInt32] = [],
        outData: Data = Data(),
        timeout: TimeInterval = 10
    ) async throws -> Data {
        let command = buildPTPCommand(operation: operation, parameters: parameters)

        print("[PTP] >> 0x\(String(operation.rawValue, radix: 16)) params=\(parameters.map { "0x" + String($0, radix: 16) }) outData=\(outData.count)B txID=\(transactionID)")

        let (dataInPayload, ptpResponse): (Data, Data) = try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.tryFire() {
                    print("[PTP] TIMEOUT for 0x\(String(operation.rawValue, radix: 16))")
                    continuation.resume(throwing: CameraError.timeout)
                }
            }

            device.requestSendPTPCommand(command, outData: outData) { dataIn, response, error in
                if once.tryFire() {
                    if let error {
                        print("[PTP] << ERROR: \(error)")
                        continuation.resume(throwing: error)
                    } else {
                        print("[PTP] << dataIn=\(dataIn.count)B response=\(response.count)B")
                        continuation.resume(returning: (dataIn, response))
                    }
                }
            }
        }

        // Validate PTP response code from the response container (second param)
        if ptpResponse.count >= 8 {
            let responseCode: UInt16 = ptpResponse.readLittleEndian(at: 6)
            if responseCode != PTPResponseCode.ok {
                print("[PTP] PTP error: 0x\(String(responseCode, radix: 16, uppercase: true))")
                throw CameraError.ptpError(responseCode)
            }
        }

        // Return data-in payload if available
        if !dataInPayload.isEmpty {
            print("[PTP] payload: \(hexDump(dataInPayload))")
            return dataInPayload
        }

        // For commands without data-in phase, return any response parameters (after 12-byte header)
        if ptpResponse.count > 12 {
            let params = Data(ptpResponse[ptpResponse.startIndex + 12 ..< ptpResponse.endIndex])
            print("[PTP] response params: \(hexDump(params))")
            return params
        }

        return Data()
    }

    // MARK: - Remote Mode

    func enableRemoteMode() async throws {
        print("[PTP] Enabling remote mode...")
        _ = try await sendCommand(operation: .setRemoteMode, parameters: [0x01])
        _ = try await sendCommand(operation: .setEventMode, parameters: [0x01])
        print("[PTP] Remote mode enabled.")
    }

    func disableRemoteMode() async throws {
        _ = try await sendCommand(operation: .setRemoteMode, parameters: [0x00])
    }

    // MARK: - Shutter

    func triggerShutter() async throws {
        _ = try await sendCommand(operation: .remoteReleaseOn, parameters: [0x03])
        try await Task.sleep(for: .milliseconds(200))
        _ = try await sendCommand(operation: .remoteReleaseOff, parameters: [0x03])
    }

    // MARK: - Properties (Canon EOS format)

    /// Sets a Canon EOS device property.
    /// Canon format: no PTP command params; data-out = [totalSize][propCode][value]
    func setProperty(_ property: CanonProperty, value: UInt32) async throws {
        var outData = Data(capacity: 12)
        outData.appendLittleEndian(UInt32(12))        // total size including this field
        outData.appendLittleEndian(property.rawValue)  // property code
        outData.appendLittleEndian(value)              // property value

        _ = try await sendCommand(
            operation: .setDevicePropValueEx,
            parameters: [],  // No command parameters for Canon EOS
            outData: outData
        )
    }

    /// Polls the camera for pending events, returns property code → value pairs.
    /// Canon EOS cameras report current property values via events after SetEventMode(1).
    func pollEvents() async throws -> [UInt32: UInt32] {
        let data = try await sendCommand(operation: .getEvent)
        return parseEventRecords(data)
    }

    private func parseEventRecords(_ data: Data) -> [UInt32: UInt32] {
        var properties: [UInt32: UInt32] = [:]
        var offset = 0

        while offset + 8 <= data.count {
            let recordSize: UInt32 = data.readLittleEndian(at: offset)
            guard recordSize >= 8, offset + Int(recordSize) <= data.count else { break }

            let recordType: UInt32 = data.readLittleEndian(at: offset + 4)

            // Property change records: type is the property code (0xD1xx range)
            if recordSize >= 12 {
                let value: UInt32 = data.readLittleEndian(at: offset + 8)
                properties[recordType] = value
            }

            offset += Int(recordSize)
            // Align to 4-byte boundary
            if offset % 4 != 0 {
                offset += 4 - (offset % 4)
            }
        }

        if !properties.isEmpty {
            print("[PTP] Events parsed: \(properties.map { "0x\(String($0.key, radix: 16))=0x\(String($0.value, radix: 16))" }.joined(separator: ", "))")
        }

        return properties
    }

    // MARK: - ISO

    func setISO(_ value: UInt32) async throws {
        try await setProperty(.iso, value: value)
    }

    // MARK: - Shutter Speed

    func setShutterSpeed(_ value: UInt32) async throws {
        try await setProperty(.shutterSpeed, value: value)
    }

    // MARK: - Live View

    func enableLiveView() async throws {
        try await setProperty(.evfMode, value: 1)
        try await setProperty(.evfOutputDevice, value: 0x02)
    }

    func disableLiveView() async throws {
        try await setProperty(.evfOutputDevice, value: 0x00)
        try await setProperty(.evfMode, value: 0)
    }

    func getLiveViewFrame() async throws -> Data {
        try await sendCommand(
            operation: .getViewFinderData,
            parameters: [0x0010_0000]
        )
    }
}
