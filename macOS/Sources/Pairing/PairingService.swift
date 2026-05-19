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

    /// Optional Cloudflare tunnel child process. Nil until the user toggles
    /// the public-tunnel switch in the menubar.
    let cloudflared: CloudflaredHost

    init() {
        let (resolvedHost, isTailscale) = Self.resolveHost()
        let resolvedToken: String
        if let data = KeychainStore.read(account: tokenAccount),
           let str = String(data: data, encoding: .utf8), !str.isEmpty {
            resolvedToken = str
        } else {
            let generated = PairingToken.shared.generate()
            KeychainStore.write(account: tokenAccount, data: Data(generated.utf8))
            resolvedToken = generated
        }
        self.host = resolvedHost
        self.hostIsTailscale = isTailscale
        self.token = resolvedToken
        self.cloudflared = CloudflaredHost(localPort: 7749)
    }

    /// True when the menubar's public-tunnel toggle is active and
    /// cloudflared has reported its assigned HTTPS URL.
    var isPublicTunnelActive: Bool {
        if case .running = cloudflared.status { return true }
        return false
    }

    /// `host:port` (LAN/Tailscale) by default, or `host:443` (tunnel) when
    /// cloudflared has handed us a public URL. The token is unchanged.
    var qrPayloadURL: String {
        if case .running(let url) = cloudflared.status,
           let publicHost = url.host {
            let publicPort = url.port ?? (url.scheme == "https" ? 443 : 80)
            return QRPayload(
                host: publicHost,
                port: Int32(publicPort),
                token: token,
                scheme: url.scheme ?? "https"
            ).toURL()
        }
        return QRPayload(host: host, port: Int32(port), token: token, scheme: "http").toURL()
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
        // Path A — Tailscale CLI binary. Works for users who installed via
        // Homebrew or the standalone CLI build.
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

        // Path B — scan local network interfaces. The Mac App Store build of
        // Tailscale ships only the GUI app (no `tailscale` CLI binary), but
        // it still assigns an IPv4 in the CGNAT range 100.64.0.0/10 to a
        // utun* interface. Pick that up directly.
        if let cgnat = tailscaleAddressFromInterfaces() {
            return (cgnat, true)
        }

        return ("127.0.0.1", false)
    }

    /// Enumerate IPv4 interfaces and return the first one whose address sits
    /// inside Tailscale's 100.64.0.0/10 CGNAT range.
    private static func tailscaleAddressFromInterfaces() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return nil }
        defer { freeifaddrs(head) }

        var current: UnsafeMutablePointer<ifaddrs>? = start
        while let node = current {
            defer { current = node.pointee.ifa_next }
            guard let addrPtr = node.pointee.ifa_addr,
                  addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(
                addrPtr,
                socklen_t(addrPtr.pointee.sa_len),
                &hostBuf,
                socklen_t(hostBuf.count),
                nil, 0,
                NI_NUMERICHOST
            )
            guard rc == 0 else { continue }
            let ip = String(cString: hostBuf)
            if isCGNAT(ip) { return ip }
        }
        return nil
    }

    private static func isCGNAT(_ ip: String) -> Bool {
        let octets = ip.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        // RFC 6598: 100.64.0.0/10 — the range Tailscale uses by default.
        return octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127
    }
}
