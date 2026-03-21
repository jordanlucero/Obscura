import SwiftUI

struct ContentView: View {
    @State private var cameraManager: CameraManager
    @State private var controlsPosition: CGPoint?
    @State private var dragOffset: CGSize = .zero

    init(cameraManager: CameraManager = CameraManager()) {
        _cameraManager = State(initialValue: cameraManager)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Live View (full bleed)
                liveViewLayer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating Controls Panel
                floatingControls
                    .position(effectivePosition(in: geometry))
                    .gesture(panelDragGesture(in: geometry))
            }
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

    // MARK: - Live View Layer

    @ViewBuilder
    private var liveViewLayer: some View {
        if cameraManager.connectionState == .connected && !cameraManager.isLiveViewActive {
            Button {
                cameraManager.startLiveView()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 72))
                    .padding()
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
            ZStack {
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
    }

    // MARK: - Floating Controls

    private var floatingControls: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 6)

            CameraControlsView(manager: cameraManager)

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
        .glassEffect()
    }

    // MARK: - Drag Positioning

    private func defaultPosition(in geometry: GeometryProxy) -> CGPoint {
        CGPoint(x: geometry.size.width / 2, y: geometry.size.height - 100)
    }

    private func effectivePosition(in geometry: GeometryProxy) -> CGPoint {
        let base = controlsPosition ?? defaultPosition(in: geometry)
        return CGPoint(
            x: base.x + dragOffset.width,
            y: base.y + dragOffset.height
        )
    }

    private func panelDragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let base = controlsPosition ?? defaultPosition(in: geometry)
                let padding: CGFloat = 60
                let newPosition = CGPoint(
                    x: min(max(base.x + value.translation.width, padding), geometry.size.width - padding),
                    y: min(max(base.y + value.translation.height, padding), geometry.size.height - padding)
                )
                withAnimation(.spring(response: 0.3)) {
                    controlsPosition = newPosition
                    dragOffset = .zero
                }
            }
    }

    // MARK: - Status

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
