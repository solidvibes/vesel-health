import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import VeselBackupKit

/// The QR, on screen only. Dropping this view drops the token.
struct PairingView: View {
    let code: PairingCode
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair your iPhone")
                .font(.headline)
            if let image = Self.qrImage(for: code.text) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Pairing code")
            }
            Text("On your iPhone: Vesel › Loop & settings › Set up backup, then scan this.")
                .fixedSize(horizontal: false, vertical: true)
            Label("This code is the key to your backup. Don't photograph or share it.", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    static func qrImage(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = (220 * 2 / output.extent.width).rounded(.down)
        let scaled = output.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
