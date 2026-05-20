import Foundation

/// Health + identity + adapter discovery — the "is this daemon reachable
/// and who is on the other end" surface. Pulled by ConnectView,
/// HomeView (dashboard greeting), and NewSessionView (provider list).
///
/// Extracted from APIClient.swift in P24.d D4 — keeps the core file
/// focused on transport, with one file per domain so each route can be
/// reviewed independently.
extension APIClient {
    /// Unauthenticated health probe. Used by PairingStore.tryPair to
    /// verify the daemon is up before persisting a token.
    func health() async throws -> Data { try await get("/health") }

    /// Greeting metadata for the dashboard home (username, full name,
    /// hostname). Pulled once on HomeView appear; cached client-side
    /// since the values don't change between launches.
    func me() async throws -> MeWire {
        let data = try await get("/me")
        return try decode(MeWire.self, from: data)
    }

    /// All CLI adapters the daemon knows about, with their installed
    /// status, version, and provider features. Drives the
    /// NewSessionView provider picker.
    func adapters() async throws -> [AdapterInfoWire] {
        let data = try await get("/adapters")
        return try decode([AdapterInfoWire].self, from: data)
    }
}
