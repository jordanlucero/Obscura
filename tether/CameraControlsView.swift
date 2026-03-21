import SwiftUI

struct CameraControlsView: View {
    var manager: CameraManager

    var body: some View {
        HStack(spacing: 32) {
            // ISO Picker — shows only camera-supported values
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
                        .fill(.red)
                        .frame(width: 60, height: 60)
                }
            }
            .buttonStyle(.plain)
            .disabled(manager.connectionState != .connected)

            // Shutter Speed Picker — shows only camera-supported values
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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
