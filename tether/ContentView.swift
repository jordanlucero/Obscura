import SwiftUI

struct ContentView: View {
    @State private var cameraManager = CameraManager()

    var body: some View {
        VStack(spacing: 0) {
            // Connection Status Bar
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .font(.subheadline)
                Spacer()
                if cameraManager.isLiveViewActive {
                    Button("Stop Live View") {
                        cameraManager.stopLiveView()
                    }
                    .font(.subheadline)
                } else if cameraManager.connectionState == .connected {
                    Button("Live View") {
                        cameraManager.startLiveView()
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            // Live View
            LiveViewDisplay(image: cameraManager.liveViewImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)

            // Camera Controls
            CameraControlsView(manager: cameraManager)
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
        case .disconnected: "No Camera"
        case .connecting: "Connecting..."
        case .connected: cameraManager.cameraName
        case .error: "Error"
        }
    }
}

#Preview {
    ContentView()
}
