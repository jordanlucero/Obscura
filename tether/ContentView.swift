import SwiftUI

struct ContentView: View {
    @State private var cameraManager: CameraManager

    init(cameraManager: CameraManager = CameraManager()) {
        _cameraManager = State(initialValue: cameraManager)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Live View area
            ZStack {
                if cameraManager.connectionState == .connected && !cameraManager.isLiveViewActive {
                    Button {
                        cameraManager.startLiveView()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 72))
                            .padding()
              //              .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .glassEffect()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if cameraManager.isLiveViewActive && cameraManager.liveViewImage == nil {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LiveViewDisplay(image: cameraManager.liveViewImage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if cameraManager.isLiveViewActive {
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    cameraManager.stopLiveView()
                                } label: {
                                    Image(systemName: "stop.fill")
                                        .font(.title2)
                                        .padding(10)
                                }
                                .buttonStyle(.plain)
                                .glassEffect()
                                .padding()
                            }
                            Spacer()
                        }
                    }
                }
            }

            // Camera Controls
            CameraControlsView(manager: cameraManager)

            // Status
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .task {
            cameraManager.startBrowsing()
        }
        .alert(
            "Camera Error",
            isPresented: .init(
                get: { cameraManager.errorMessage != nil },
                set: { if !$0 { cameraManager.errorMessage = nil } }
            )
        ) {
            Button("OK") { cameraManager.errorMessage = nil }
        } message: {
            Text(cameraManager.errorMessage ?? "")
        }
    }

    private var statusColor: Color {
        switch cameraManager.connectionState {
        case .disconnected: .gray
        case .connecting: .yellow
        case .connected: .green
        case .error: .red
        }
    }

    private var statusText: String {
        switch cameraManager.connectionState {
        case .disconnected: "Not Connected"
        case .connecting: "Connecting..."
        case .connected: cameraManager.cameraName
        case .error: "Error"
        }
    }
}

#Preview("No Camera") {
    ContentView()
}

#Preview("Connected — Live View Off") {
    ContentView(cameraManager: .preview(state: .connected))
}

#Preview("Live View Warming Up") {
    ContentView(cameraManager: .preview(state: .connected, isLiveViewActive: true))
}
