import Foundation

extension Date {
    /// Compact relative-time string ("just now" / "12m ago" / "3h ago" /
    /// "2d ago" / "1w ago" / "long ago"). Used in HomeView and the folder
    /// picker so timestamps stay scannable on a small mobile row.
    var relative: String {
        let interval = Date.now.timeIntervalSince(self)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d ago" }
        let weeks = Int(interval / 604_800)
        return weeks < 4 ? "\(weeks)w ago" : "long ago"
    }
}
