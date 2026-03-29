import SwiftUI

struct CameraControlsView: View {
    var manager: CameraManager
    @State private var isFocusPanelExpanded = false
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            mainControlsRow

            if isFocusPanelExpanded {
                focusStepPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isFocusPanelExpanded)
    }

    // MARK: - Main Controls Row

    private var mainControlsRow: some View {
        HStack(spacing: 24) {
            // More Menu
            Menu {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }

            // ISO Picker
            Menu {
                ForEach(manager.availableISOs) { iso in
                    Button(iso.name) {
                        manager.setISO(iso)
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Text("ISO")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(manager.currentISO)
                        .font(.title3.monospacedDigit().bold())
                }
                .frame(minWidth: 70)
            }

            // Shutter Button
            Button {
                manager.triggerShutter()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(.white)
                        .frame(width: 60, height: 60)
                }
            }
            .buttonStyle(.plain)
            .disabled(manager.connectionState != .connected)

            // Shutter Speed Picker
            Menu {
                ForEach(manager.availableShutterSpeeds) { speed in
                    Button(speed.name) {
                        manager.setShutterSpeed(speed)
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Text("Tv")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(manager.currentShutterSpeed)
                        .font(.title3.monospacedDigit().bold())
                }
                .frame(minWidth: 70)
            }

            // Focus Toggle
            Button {
                isFocusPanelExpanded.toggle()
            } label: {
                Image(systemName: "scope")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(isFocusPanelExpanded ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!manager.isLiveViewActive)
            .onChange(of: manager.isLiveViewActive) { _, active in
                if !active {
                    isFocusPanelExpanded = false
                }
            }
        }
    }

    // MARK: - Focus Step Panel

    private var focusStepPanel: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 8)

            HStack(spacing: 16) {
                // Near focus (toward camera)
                HStack(spacing: 8) {
                    Text("NEAR")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    ForEach(FocusStep.nearSteps, id: \.parameterValue) { step in
                        focusStepButton(step: step)
                    }
                }

                Spacer()

                // Far focus (toward infinity)
                HStack(spacing: 8) {
                    ForEach(FocusStep.farSteps, id: \.parameterValue) { step in
                        focusStepButton(step: step)
                    }

                    Text("FAR")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func focusStepButton(step: FocusStep) -> some View {
        Button {
            manager.driveLens(step: step)
        } label: {
            Image(systemName: step.symbolName)
                .font(.title2)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
