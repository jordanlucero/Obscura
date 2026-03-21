import SwiftUI

struct LiveViewDisplay: View {
    let image: CGImage?

    private var connectionDescription: String {
        #if os(macOS)
        return "To start, connect a camera to an available USB port on your Mac and make sure its on."
        #elseif os(visionOS)
        return "To start, connect a camera to your Apple Vision Pro using an available USB port and make sure its on. You may need a developer strap."
        #else
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return "To start, connect a camera to your iPad over USB and make sure its on."
        default:
            return "To start, connect a camera to your iPhone over USB and make sure its on."
        }
        #endif
    }

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1.0, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ContentUnavailableView(
                "Tether Is Ready",
                systemImage: "camera.badge.ellipsis.fill",
                description: Text(connectionDescription)
            )
        }
    }
}
