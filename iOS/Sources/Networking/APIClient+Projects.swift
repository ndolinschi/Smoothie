import Foundation

/// Project discovery + file browse surfaces. Used by FolderPickerSheet
/// (project list + drill-in browse), MentionPickerSheet (file list +
/// content fetch), and SessionView's repo chip (project metadata).
///
/// Extracted from APIClient.swift in P24.d D4.
extension APIClient {
    /// Top-level project directories under the configured roots
    /// (`~/Developer`, `~/Documents`, etc.). Used by HomeView's folder
    /// picker for the initial "Open a folder" list.
    func projects() async throws -> [ProjectWire] {
        let data = try await get("/projects")
        return try decode([ProjectWire].self, from: data)
    }

    /// Directory browser. Pass `nil` for the configured roots, or a
    /// subfolder path for the contents of that folder (with parent
    /// breadcrumb + git-first sorting on the daemon side).
    func browse(path: String? = nil) async throws -> BrowseResponseWire {
        let p: String
        if let path {
            p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        } else {
            p = ""
        }
        let route = p.isEmpty ? "/browse" : "/browse?path=\(p)"
        let data = try await get(route)
        return try decode(BrowseResponseWire.self, from: data)
    }

    /// Recursive file listing for the mention picker.
    func projectFiles(path: String, query: String = "") async throws -> [FileEntryWire] {
        let p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await get("/projects/files?path=\(p)&q=\(q)")
        return try decode([FileEntryWire].self, from: data)
    }

    /// Single text file contents, 4 MB cap with `truncated` flag set
    /// when the file exceeded that limit (server-side per P24.b B1).
    func fileContent(path: String) async throws -> FileContentWire {
        let p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let data = try await get("/projects/file?path=\(p)")
        return try decode(FileContentWire.self, from: data)
    }
}
