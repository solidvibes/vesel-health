import SwiftUI
import VisionKit

/// Scans the set-up QR the Mac shows. The camera picture stays on the phone.
struct BackupScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScanner(onScan: onScan).ignoresSafeArea()
                } else {
                    Text(
                        DataScannerViewController.isSupported
                            ? "Vesel can't use the camera. Allow it in iOS Settings › Vesel › Camera, then try again."
                            : "This iPhone can't scan QR codes here."
                    )
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.s24)
                }
            }
            .navigationTitle("Scan the QR on your Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var scanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !scanned else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue {
                    scanned = true
                    scanner.stopScanning()
                    onScan(text)
                    return
                }
            }
        }
    }
}
