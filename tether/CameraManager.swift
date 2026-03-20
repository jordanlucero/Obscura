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

    // MARK: - Internal

    @ObservationIgnored private var browser: ICDeviceBrowser?
    @ObservationIgnored private var connectedDevice: ICCameraDevice?
    @ObservationIgnored private var ptpService: CanonPTPService?
    @ObservationIgnored private var liveViewTask: Task<Void, Never>?

    // Canon USB vendor ID
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
        guard let ptpService else { return }
        Task {
            do {
                try await ptpService.setISO(iso.code)
                // Poll events to confirm the camera accepted the change
                let props = try await ptpService.pollEvents()
                if let newISO = props[CanonProperty.iso.rawValue] {
                    self.currentISO = ISOValue.name(for: newISO)
                } else {
                    self.currentISO = iso.name
                }
            } catch {
                self.errorMessage = "Set ISO failed: \(error.localizedDescription)"
            }
        }
    }

    func setShutterSpeed(_ speed: ShutterSpeedValue) {
        guard let ptpService else { return }
        Task {
            do {
                try await ptpService.setShutterSpeed(speed.code)
                let props = try await ptpService.pollEvents()
                if let newTv = props[CanonProperty.shutterSpeed.rawValue] {
                    self.currentShutterSpeed = ShutterSpeedValue.name(for: newTv)
                } else {
                    self.currentShutterSpeed = speed.name
                }
            } catch {
                self.errorMessage = "Set shutter speed failed: \(error.localizedDescription)"
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

    // MARK: - Session Setup

    private func initializeRemoteControl(device: ICCameraDevice) {
        let service = CanonPTPService(device: device)
        ptpService = service

        Task {
            do {
                try await service.enableRemoteMode()

                // Canon EOS reports current property values as events after SetEventMode(1).
                // Poll to read the initial state.
                let props = try await service.pollEvents()
                if let iso = props[CanonProperty.iso.rawValue] {
                    self.currentISO = ISOValue.name(for: iso)
                }
                if let tv = props[CanonProperty.shutterSpeed.rawValue] {
                    self.currentShutterSpeed = ShutterSpeedValue.name(for: tv)
                }

                self.connectionState = .connected
                print("[Camera] Fully connected — ISO=\(self.currentISO) Tv=\(self.currentShutterSpeed)")
            } catch {
                self.connectionState = .error
                self.errorMessage = "Setup failed: \(error.localizedDescription)"
                print("[Camera] Setup failed: \(error)")
            }
        }
    }

    // MARK: - JPEG Extraction

    private func extractJPEG(from data: Data) -> CGImage? {
        guard data.count > 2 else { return nil }

        // Scan for JPEG SOI marker (0xFF 0xD8)
        var soiOffset: Int?
        for i in 0..<(data.count - 1) {
            if data[data.startIndex + i] == 0xFF && data[data.startIndex + i + 1] == 0xD8 {
                soiOffset = i
                break
            }
        }
        guard let soi = soiOffset else { return nil }

        // Scan for JPEG EOI marker (0xFF 0xD9) from SOI
        var eoiOffset: Int?
        for i in (soi + 2)..<(data.count - 1) {
            if data[data.startIndex + i] == 0xFF && data[data.startIndex + i + 1] == 0xD9 {
                eoiOffset = i + 2 // include the EOI marker
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

// MARK: - ICDeviceBrowserDelegate

extension CameraManager: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        let name = device.name ?? "unknown"
        let vendorID = device.usbVendorID
        print("[Camera] Browser found device: \(name) (vendorID=0x\(String(vendorID, radix: 16)), type=\(device.type), moreComing=\(moreComing))")
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
        // Only accept Canon cameras connected via USB
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
                // Don't send PTP commands yet — wait for deviceDidBecomeReady
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
