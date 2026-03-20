import SwiftUI

struct LiveViewDisplay: View {
    let image: CGImage?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1.0, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ContentUnavailableView(
                "No Live View",
                systemImage: "camera.fill",
                description: Text("Connect a camera and enable live view to see the preview here.")
            )
        }
    }
}
