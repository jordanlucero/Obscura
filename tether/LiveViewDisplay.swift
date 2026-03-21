import SwiftUI

struct LiveViewDisplay: View {
    let image: CGImage?

    private var connectionDescription: String {
        #if os(macOS)
        return "To start, connect your camera to an available USB port on your Mac and make sure it's on."
        #elseif os(visionOS)
        return "To start, connect a camera to your Apple Vision Pro over USB via Developer Strap on make sure it's on."
        #else
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return "To start, connect your camera to your iPad over USB and make sure it's on."
        default:
            return "To start, connect your camera to your iPhone over USB and make sure it's on."
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
