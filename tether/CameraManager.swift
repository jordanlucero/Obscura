@preconcurrency import ImageCaptureCore
import ImageIO
import Foundation

@Observable
class CameraManager: NSObject {

    // MARK: - Published State

    var connectionState: ConnectionState = .disconnected
    var cameraName: String = ""
    var currentISO: String = "---"
    var currentShutterSpeed: String = "---"
    var liveViewImage: CGImage?
    var isLiveViewActive: Bool = false
    var errorMessage: String?

    /// Available ISO values reported by the connected camera.
    var availableISOs: [ISOValue] = ISOValue.all
    /// Available shutter speed values reported by the connected camera.
    var availableShutterSpeeds: [ShutterSpeedValue] = ShutterSpeedValue.all

    // MARK: - Internal

    @ObservationIgnored private var browser: ICDeviceBrowser?
    @ObservationIgnored private var connectedDevice: ICCameraDevice?
    @ObservationIgnored private var ptpService: CanonPTPService?
    @ObservationIgnored private var liveViewTask: Task<Void, Never>?

    private static let canonVendorID = 0x04A9

    // MARK: - Browsing

    func startBrowsing() {
        guard browser == nil else { return }
        print("[Camera] Starting browser...")
        connectionState = .disconnected
        let b = ICDeviceBrowser()
        b.delegate = self
        b.start()
        browser = b
    }

    func stopBrowsing() {
        stopLiveView()
        browser?.stop()
        browser = nil
        if let device = connectedDevice {
            device.requestCloseSession()
        }
        connectedDevice = nil
        ptpService = nil
        connectionState = .disconnected
        cameraName = ""
    }

    // MARK: - Camera Actions

    func triggerShutter() {
        guard let ptpService else { return }
        Task {
            do {
                try await ptpService.triggerShutter()
            } catch {
                self.errorMessage = "Shutter failed: \(error.localizedDescription)"
            }
        }
    }

    func setISO(_ iso: ISOValue) {
        currentISO = iso.name           // optimistic — camera confirmation follows
        guard let ptpService else { return }
        Task {
            do {
                try await ptpService.setISO(iso.code)
                let events = try await ptpService.pollEvents()
                applyEventResults(events)
            } catch {
                self.errorMessage = "Set ISO failed: \(error.localizedDescription)"
            }
        }
    }

    func setShutterSpeed(_ speed: ShutterSpeedValue) {
        currentShutterSpeed = speed.name // optimistic — camera confirmation follows
        guard let ptpService else { return }
        Task {
            do {
                try await ptpService.setShutterSpeed(speed.code)
                let events = try await ptpService.pollEvents()
                applyEventResults(events)
            } catch {
                self.errorMessage = "Set shutter speed failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Focus

    func driveLens(step: FocusStep) {
        guard let ptpService, isLiveViewActive else { return }
        Task {
            do {
                try await ptpService.driveLens(step: step)
            } catch {
                self.errorMessage = "Focus failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Live View

    func startLiveView() {
        guard let ptpService, !isLiveViewActive else { return }
        isLiveViewActive = true

        liveViewTask = Task {
            do {
                try await ptpService.enableLiveView()
            } catch {
                self.isLiveViewActive = false
                self.errorMessage = "Live view failed: \(error.localizedDescription)"
                return
            }

            while !Task.isCancelled && isLiveViewActive {
                do {
                    let frameData = try await ptpService.getLiveViewFrame()
                    if let image = extractJPEG(from: frameData) {
                        self.liveViewImage = image
                    }
                } catch {
                    // Frame fetch can fail transiently; continue polling
                }
                try? await Task.sleep(for: .milliseconds(67)) // ~15fps
            }

            try? await ptpService.disableLiveView()
        }
    }

    func stopLiveView() {
        isLiveViewActive = false
        liveViewTask?.cancel()
        liveViewTask = nil
        liveViewImage = nil
    }

    // MARK: - Authorization & Session Setup

    /// Requests control authorization (required on iPadOS for PTP commands).
    /// On macOS this is not needed — returns true immediately.
    private func requestControlAuthorizationIfNeeded() async -> Bool {
        #if os(iOS) || os(visionOS)
        guard let browser else { return false }

        let status = browser.controlAuthorizationStatus
        print("[Camera] Current control authorization: \(status.rawValue)")

        if status == .authorized { return true }

        let newStatus = await withCheckedContinuation { continuation in
            browser.requestControlAuthorization { s in
                continuation.resume(returning: s)
            }
        }
        print("[Camera] Control authorization result: \(newStatus.rawValue)")
        return newStatus == .authorized
        #else
        return true
        #endif
    }

    private func initializeRemoteControl(device: ICCameraDevice) {
        let service = CanonPTPService(device: device)
        ptpService = service

        Task {
            // Request control authorization (critical on iPadOS, no-op on macOS if already authorized)
            let authorized = await requestControlAuthorizationIfNeeded()
            if !authorized {
                self.connectionState = .error
                self.errorMessage = "Tether needs permission to connect to your camera. Please make sure Tether has Files & Folders and Camera permissions in Settings > Privacy & Security."
                print("[Camera] Control authorization denied.")
                return
            }

            do {
                try await service.enableRemoteMode()

                // Canon EOS reports current values and available values as events
                let events = try await service.pollEvents()
                applyEventResults(events)

                self.connectionState = .connected
                print("[Camera] Fully connected — ISO=\(self.currentISO) Tv=\(self.currentShutterSpeed)")
            } catch {
                self.connectionState = .error
                self.errorMessage = "Setup failed: \(error.localizedDescription)"
                print("[Camera] Setup failed: \(error)")
            }
        }
    }

    // MARK: - Event Handling

    private func applyEventResults(_ events: EventPollResult) {
        // Update current values
        if let iso = events.currentValues[CanonProperty.iso.rawValue] {
            currentISO = ISOValue.name(for: iso)
        }
        if let tv = events.currentValues[CanonProperty.shutterSpeed.rawValue] {
            currentShutterSpeed = ShutterSpeedValue.name(for: tv)
        }

        // Update available value lists (filter our static table to only camera-supported values)
        if let isoList = events.availableValues[CanonProperty.iso.rawValue], !isoList.isEmpty {
            let matched = isoList.compactMap { code in ISOValue.all.first { $0.code == code } }
            print("[Camera] ISO codes from camera: \(isoList.map { "0x\(String($0, radix: 16))" }.joined(separator: ",")) → matched \(matched.count)/\(isoList.count)")
            if !matched.isEmpty {
                availableISOs = matched
                print("[Camera] Available ISOs: \(availableISOs.map(\.name).joined(separator: ", "))")
            }
        }
        if let tvList = events.availableValues[CanonProperty.shutterSpeed.rawValue], !tvList.isEmpty {
            let matched = tvList.compactMap { code in ShutterSpeedValue.all.first { $0.code == code } }
            print("[Camera] Tv codes from camera: \(tvList.map { "0x\(String($0, radix: 16))" }.joined(separator: ",")) → matched \(matched.count)/\(tvList.count)")
            if !matched.isEmpty {
                availableShutterSpeeds = matched
                print("[Camera] Available Tv: \(availableShutterSpeeds.map(\.name).joined(separator: ", "))")
            }
        }
    }

    // MARK: - JPEG Extraction

    private func extractJPEG(from data: Data) -> CGImage? {
        guard data.count > 2 else { return nil }

        var soiOffset: Int?
        for i in 0..<(data.count - 1) {
            if data[data.startIndex + i] == 0xFF && data[data.startIndex + i + 1] == 0xD8 {
                soiOffset = i
                break
            }
        }
        guard let soi = soiOffset else { return nil }

        var eoiOffset: Int?
        for i in (soi + 2)..<(data.count - 1) {
            if data[data.startIndex + i] == 0xFF && data[data.startIndex + i + 1] == 0xD9 {
                eoiOffset = i + 2
                break
            }
        }
        guard let eoi = eoiOffset else { return nil }

        let jpegData = data[data.startIndex + soi ..< data.startIndex + eoi]
        guard let source = CGImageSourceCreateWithData(Data(jpegData) as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }
}

// MARK: - Preview Support

#if DEBUG
extension CameraManager {
    static func preview(
        state: ConnectionState,
        cameraName: String = "Canon EOS R5",
        isLiveViewActive: Bool = false
    ) -> CameraManager {
        let m = CameraManager()
        m.connectionState = state
        m.cameraName = cameraName
        m.isLiveViewActive = isLiveViewActive
        m.currentISO = "400"
        m.currentShutterSpeed = "1/125"
        return m
    }
}
#endif

// MARK: - ICDeviceBrowserDelegate

extension CameraManager: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        let name = device.name ?? "unknown"
        let vendorID = device.usbVendorID
        print("[Camera] Browser found device: \(name) (vendorID=0x\(String(vendorID, radix: 16)), moreComing=\(moreComing))")
        Task { @MainActor in
            self.handleDeviceAdded(device)
        }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        print("[Camera] Browser removed device: \(device.name ?? "unknown")")
        Task { @MainActor in
            self.handleDeviceRemoved(device)
        }
    }

    private func handleDeviceAdded(_ device: ICDevice) {
        guard let camera = device as? ICCameraDevice,
              camera.usbVendorID == Self.canonVendorID else {
            print("[Camera] Ignoring non-Canon device: \(device.name ?? "unknown")")
            return
        }

        print("[Camera] Canon camera found! Opening session...")
        connectionState = .connecting
        cameraName = camera.name ?? "Canon Camera"
        camera.delegate = self
        camera.requestOpenSession()
    }

    private func handleDeviceRemoved(_ device: ICDevice) {
        guard device === connectedDevice else { return }
        print("[Camera] Connected device removed.")
        stopLiveView()
        connectedDevice = nil
        ptpService = nil
        connectionState = .disconnected
        cameraName = ""
        currentISO = "---"
        currentShutterSpeed = "---"
        availableISOs = ISOValue.all
        availableShutterSpeeds = ShutterSpeedValue.all
    }
}

// MARK: - ICCameraDeviceDelegate

extension CameraManager: ICCameraDeviceDelegate {
    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        print("[Camera] didOpenSession — error=\(error?.localizedDescription ?? "none")")
        Task { @MainActor in
            if let error {
                self.connectionState = .error
                self.errorMessage = "Session failed: \(error.localizedDescription)"
                return
            }
            if let camera = device as? ICCameraDevice {
                self.connectedDevice = camera
                print("[Camera] Session opened. Waiting for device to become ready...")
            }
        }
    }

    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        print("[Camera] deviceDidBecomeReady — starting PTP initialization")
        Task { @MainActor in
            self.initializeRemoteControl(device: device)
        }
    }

    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        print("[Camera] didCloseSession — error=\(error?.localizedDescription ?? "none")")
        Task { @MainActor in
            self.handleDeviceRemoved(device)
        }
    }

    nonisolated func didRemove(_ device: ICDevice) {
        print("[Camera] didRemove")
        Task { @MainActor in
            self.handleDeviceRemoved(device)
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        print("[Camera] didAdd \(items.count) items")
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: (any Error)?) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: (any Error)?) {}

    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
        print("[Camera] cameraDeviceDidChangeCapability")
    }

    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        print("[Camera] cameraDeviceDidRemoveAccessRestriction")
    }

    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        print("[Camera] cameraDeviceDidEnableAccessRestriction")
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {
        print("[Camera] didReceivePTPEvent — \(eventData.count) bytes")
    }
}
