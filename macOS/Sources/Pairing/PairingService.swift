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

        // Path B — Tailscale's macOS GUI build (App Store) ships no CLI
        // binary, but it does install /Applications/Tailscale.app. Only run
        // the CGNAT interface scan when the GUI is actually present, so we
        // don't misattribute another VPN client's 100.64.0.0/10 utun (NordVPN
        // and a few others sit in the same RFC 6598 range) as Tailscale.
        if isTailscaleGUIInstalled(), let cgnat = tailscaleAddressFromInterfaces() {
            return (cgnat, true)
        }

        // Path C — No Tailscale at all. Scan for the Mac's primary LAN
        // address (RFC 1918 private ranges) so the QR code encodes a host
        // the phone can actually reach on the same network. Prefer en0
        // (Wi-Fi) then en1 (Ethernet), then accept any private-range match.
        if let lan = lanAddressFromInterfaces() {
            return (lan, false)
        }

        return ("127.0.0.1", false)
    }

    private static func isTailscaleGUIInstalled() -> Bool {
        let fm = FileManager.default
        let candidates = [
            "/Applications/Tailscale.app",
            "\(NSHomeDirectory())/Applications/Tailscale.app",
        ]
        return candidates.contains { fm.fileExists(atPath: $0) }
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

    /// Scan network interfaces for a private LAN IPv4 address. Tries the
    /// canonical Wi-Fi (en0) and Ethernet (en1) interfaces first so we
    /// return the "primary" adapter on most Macs, then falls back to any
    /// other interface that carries a private-range address.
    private static func lanAddressFromInterfaces() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return nil }
        defer { freeifaddrs(head) }

        // Two-pass: preferred interfaces first, then anything else.
        let preferred = ["en0", "en1"]
        var fallback: String?

        var node: UnsafeMutablePointer<ifaddrs>? = start
        while let current = node {
            defer { node = current.pointee.ifa_next }
            guard let addrPtr = current.pointee.ifa_addr,
                  addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                addrPtr, socklen_t(addrPtr.pointee.sa_len),
                &buf, socklen_t(buf.count),
                nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }

            let ip = String(cString: buf)
            guard isPrivateLAN(ip) else { continue }

            let name = String(cString: current.pointee.ifa_name)
            if preferred.contains(name) { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }

    /// True for RFC 1918 private ranges (10/8, 172.16/12, 192.168/16).
    private static func isPrivateLAN(_ ip: String) -> Bool {
        let o = ip.split(separator: ".").compactMap { UInt8($0) }
        guard o.count == 4 else { return false }
        return o[0] == 10
            || (o[0] == 172 && o[1] >= 16 && o[1] <= 31)
            || (o[0] == 192 && o[1] == 168)
    }
}
