import Foundation
import Hummingbird
import Logging

let startedAt = Date()
let config = Config.resolve()

let sleep = SleepPrevention()
sleep.enable()

let registry = AdapterRegistry()
await registry.discoverAll()

let manager = SessionManager()

let router = APIRouter.build(
    config: config,
    registry: registry,
    manager: manager,
    startedAt: startedAt
)

var logger = Logger(label: "smoothie")
logger.logLevel = .info

let app = Application(
    router: router,
    configuration: .init(
        address: .hostname(config.bindAddress, port: config.port),
        serverName: "Smoothie"
    ),
    logger: logger
)

let bindHint = config.bindAddressIsTailscale ? "(Tailscale)" : "(local-only)"
let bindAddress = config.bindAddress
let port = config.port
let info = await registry.info
let adapterSummary = info
    .map { "\($0.cli.rawValue)=\($0.installed ? ($0.supported ? "ok" : "stub") : "missing")" }
    .joined(separator: " ")

FileHandle.standardError.write(Data("\n".utf8))
FileHandle.standardError.write(Data("\u{001B}[1;32m▶ Smoothie\u{001B}[0m server listening on http://\(bindAddress):\(port) \(bindHint)\n".utf8))
FileHandle.standardError.write(Data("  adapters: \(adapterSummary)\n".utf8))
FileHandle.standardError.write(Data("  allowed:  \(config.allowedRoots.joined(separator: ", "))\n\n".utf8))

do {
    try await app.runService()
} catch {
    FileHandle.standardError.write(Data("[smoothie] server error: \(error)\n".utf8))
    await manager.terminateAll()
    sleep.disable()
    throw error
}
await manager.terminateAll()
sleep.disable()
