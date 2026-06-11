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
        let p = path?.queryValueEncoded ?? ""
        let route = p.isEmpty ? "/browse" : "/browse?path=\(p)"
        let data = try await get(route)
        return try decode(BrowseResponseWire.self, from: data)
    }

    /// Recursive file listing for the mention picker.
    func projectFiles(path: String, query: String = "") async throws -> [FileEntryWire] {
        let p = path.queryValueEncoded
        let q = query.queryValueEncoded
        let data = try await get("/projects/files?path=\(p)&q=\(q)")
        return try decode([FileEntryWire].self, from: data)
    }

    /// Single text file contents, 4 MB cap with `truncated` flag set
    /// when the file exceeded that limit (server-side per P24.b B1).
    func fileContent(path: String) async throws -> FileContentWire {
        let data = try await get("/projects/file?path=\(path.queryValueEncoded)")
        return try decode(FileContentWire.self, from: data)
    }
}

private extension String {
    /// Percent-encode for use as a single query VALUE. `.urlQueryAllowed`
    /// describes the whole query component, so it leaves `&`, `=`, `+`,
    /// `?` and `#` bare — a folder name containing any of those split the
    /// value at the daemon's query parser and 403'd the request.
    var queryValueEncoded: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
