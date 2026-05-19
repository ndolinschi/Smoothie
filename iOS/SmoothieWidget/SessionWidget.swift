import WidgetKit
import SwiftUI

struct SessionEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SessionTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionEntry {
        SessionEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionEntry) -> Void) {
        completion(SessionEntry(date: .now, snapshot: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.read()
        let entry = SessionEntry(date: .now, snapshot: snapshot)
        // Refresh every 15 minutes as a fallback. The host app calls
        // `WidgetCenter.reloadAllTimelines()` on state changes for near-real-
        // time updates while it's running.
        let next = Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SessionWidget: Widget {
    let kind: String = "SmoothieSessionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SessionTimelineProvider()) { entry in
            SessionWidgetView(snapshot: entry.snapshot)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Smoothie Session")
        .description("Shows the state of your most recent Smoothie session.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}
