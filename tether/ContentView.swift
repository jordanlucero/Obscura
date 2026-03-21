import SwiftUI

struct ContentView: View {
    @State private var cameraManager: CameraManager
    @State private var controlsPosition: CGPoint?
    @State private var dragOffset: CGSize = .zero

    #if os(macOS)
    @State private var onAirPulse = false
    @State private var isHoveringLive = false
    #else
    @State private var showingStopOverlay = false
    #endif

    init(cameraManager: CameraManager = CameraManager()) {
        _cameraManager = State(initialValue: cameraManager)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                liveViewLayer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                #if !os(macOS)
                if cameraManager.isLiveViewActive && cameraManager.liveViewImage != nil {
                    stopOverlay
                }
                #endif

                floatingControls
                    .position(effectivePosition(in: geometry))
                    .gesture(panelDragGesture(in: geometry))
            }
        }
        #if !os(macOS)
        .onChange(of: cameraManager.isLiveViewActive) { _, active in
            if !active { showingStopOverlay = false }
        }
        #endif
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
            LiveViewDisplay(image: cameraManager.liveViewImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - iOS/iPadOS Stop Overlay

    #if !os(macOS)
    private var stopOverlay: some View {
        ZStack {
            // Invisible tap target — always present over the live view
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingStopOverlay.toggle()
                    }
                }

            if showingStopOverlay {
                // Dim
                Color.black.opacity(0.3)
                    .allowsHitTesting(false)
                    .transition(.opacity)

                // Stop button
                Button {
                    cameraManager.stopLiveView()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingStopOverlay = false
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .padding(20)
                }
                .buttonStyle(.plain)
                .glassEffect()
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .task(id: showingStopOverlay) {
            guard showingStopOverlay else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeInOut(duration: 0.3)) {
                showingStopOverlay = false
            }
        }
    }
    #endif

    // MARK: - Floating Controls

    private var floatingControls: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 6)

            CameraControlsView(manager: cameraManager)

            statusOrStopView
                .padding(.vertical, 8)
        }
        .glassEffect()
    }

    @ViewBuilder
    private var statusOrStopView: some View {
        #if os(macOS)
        if cameraManager.isLiveViewActive {
            Button {
                cameraManager.stopLiveView()
            } label: {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                        Image(systemName: "stop.fill")
                            .font(.system(size: 5, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(isHoveringLive ? 1 : 0)
                    }
                    Text("LIVE")
                        .font(.footnote.monospaced().bold())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .background(.red.opacity(onAirPulse ? 0.15 : 0.0), in: Capsule())
            .glassEffect()
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHoveringLive = hovering
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    onAirPulse = true
                }
            }
            .onDisappear {
                onAirPulse = false
                isHoveringLive = false
            }
        } else {
            statusLine
        }
        #else
        statusLine
        #endif
    }

    private var statusLine: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
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
