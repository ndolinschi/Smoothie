import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Observation
import Shared

/// Owns the pairing token (Keychain-persisted) and the server's bind address.
/// Generates the `smoothie://pair?...` URL and the QR image for the macOS UI.
@MainActor
@Observable
final class PairingService {
    private let tokenAccount = "pairing-token"

    private(set) var token: String
    private(set) var host: String
    let port: Int = 7749
    private(set) var hostIsTailscale: Bool

    init() {
        let (resolvedHost, isTailscale) = Self.resolveHost()
        self.host = resolvedHost
        self.hostIsTailscale = isTailscale
        if let data = KeychainStore.read(account: tokenAccount),
           let str = String(data: data, encoding: .utf8), !str.isEmpty {
            self.token = str
        } else {
            self.token = PairingToken.shared.generate()
            KeychainStore.write(account: tokenAccount, data: Data(self.token.utf8))
        }
    }

    var qrPayloadURL: String {
        QRPayload(host: host, port: Int32(port), token: token).toURL()
    }

    func rotate() {
        token = PairingToken.shared.generate()
        KeychainStore.write(account: tokenAccount, data: Data(token.utf8))
    }

    func refreshHost() {
        let (resolvedHost, isTailscale) = Self.resolveHost()
        host = resolvedHost
        hostIsTailscale = isTailscale
    }

    func qrImage(pixelSize: CGFloat = 360) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(qrPayloadURL.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let outputBase = output.extent.width
        let scale = max(1, pixelSize / outputBase)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }

    private static func resolveHost() -> (String, Bool) {
        for path in ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale"] {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = ["ip", "-4"]
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                if let raw = String(data: data, encoding: .utf8) {
                    let lines = raw.split(whereSeparator: { $0.isNewline || $0.isWhitespace })
                    if let ip = lines.first, ip.contains(".") {
                        return (String(ip), true)
                    }
                }
            } catch { }
        }
        return ("127.0.0.1", false)
    }
}
