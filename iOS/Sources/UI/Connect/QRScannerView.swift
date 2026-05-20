import AVFoundation
import SwiftUI
import UIKit

/// AVFoundation-powered QR scanner. Calls `onScan(text)` with the decoded
/// string each time a frame contains a valid QR. The parent view decides
/// whether to accept or keep scanning.
///
/// Surfaces explicit camera-permission state via `onPermissionDenied` so
/// the parent can show an actionable "Open Settings" card instead of the
/// silent black-screen failure mode we used to land in when the user had
/// denied camera access (or hit the OS prompt and tapped Don't Allow).
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    /// Fires when the user has denied or restricted camera access. The
    /// scanner controller will render an empty black view; the parent is
    /// expected to switch to a friendlier prompt.
    var onPermissionDenied: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.onScan = onScan
        c.onPermissionDenied = onPermissionDenied
        return c
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        var onScan: ((String) -> Void)?
        var onPermissionDenied: (() -> Void)?
        private var lastEmitted: String?
        private var emittedAt: Date = .distantPast

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            ensurePermissionThenConfigure()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.startRunning()
                }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.layer.bounds
        }

        /// Resolve the camera-authorization state before touching
        /// `AVCaptureSession`. Without this, a `denied`/`restricted`
        /// user lands on a black screen with no preview and no error
        /// — they don't know whether the scanner is broken or whether
        /// they need to enable a permission.
        private func ensurePermissionThenConfigure() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configureSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if granted {
                            self.configureSession()
                        } else {
                            self.onPermissionDenied?()
                        }
                    }
                }
            case .denied, .restricted:
                fallthrough
            @unknown default:
                onPermissionDenied?()
            }
        }

        private func configureSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                onPermissionDenied?()
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.metadataObjectTypes = [.qr]
            output.setMetadataObjectsDelegate(self, queue: .main)

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            previewLayer = layer

            // `viewDidAppear` may have already fired (presented before
            // permission resolved) — kick the session ourselves so the
            // preview shows without waiting for another lifecycle pass.
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.startRunning()
                }
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  obj.type == .qr,
                  let str = obj.stringValue else { return }
            // Debounce duplicate emissions
            if str == lastEmitted, Date().timeIntervalSince(emittedAt) < 1.5 { return }
            lastEmitted = str
            emittedAt = Date()
            onScan?(str)
        }
    }
}
