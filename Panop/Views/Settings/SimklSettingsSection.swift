import CoreImage.CIFilterBuiltins
import PanopSimkl
import SwiftUI

/// Connecting a Simkl account: a code to approve on a phone or computer, shown with a QR code so a
/// television needs no typing.
struct SimklSettingsSection: View {
    @Environment(SimklAccount.self) private var account

    var body: some View {
        Section {
            switch account.state {
            case .signedOut:
                Button("Connect Simkl") { Task { await account.signIn() } }
            case let .waiting(code):
                waiting(code)
            case .connected:
                LabeledContent("Simkl", value: "Connected")
                Button("Disconnect", role: .destructive) { Task { await account.signOut() } }
            case let .failed(failure):
                Text(failure == .codeExpired ? "The code ran out before it was approved." :
                    "Simkl could not be reached.")
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await account.signIn() } }
            }
        } header: {
            Text("Simkl")
        } footer: {
            Text("Connecting lets Panop keep your watched titles and lists in step with your Simkl account.")
        }
    }

    @ViewBuilder
    private func waiting(_ code: SimklDeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On your phone or computer, go to")
            Text(code.verificationURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                .font(.headline)
            Text("and enter")
            Text(code.userCode)
                .font(.system(.largeTitle, design: .monospaced).bold())
                .accessibilityLabel("Code \(code.userCode)")
            if let image = QRCode.image(for: (code.verificationURLComplete ?? code.verificationURL).absoluteString) {
                image
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 160, height: 160)
                    .accessibilityHidden(true)
            }
            ProgressView("Waiting for approval…")
        }
        .padding(.vertical, 4)
        Button("Cancel") { account.cancelSignIn() }
    }
}

private enum QRCode {
    static func image(for text: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}
