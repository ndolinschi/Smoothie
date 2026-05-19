import SwiftUI

struct AgentStream: View {
    let events: [SmoothieEventWire]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(events) { event in
                        EventRow(event: event)
                            .id(event.id)
                    }
                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: events.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
        }
    }
}
