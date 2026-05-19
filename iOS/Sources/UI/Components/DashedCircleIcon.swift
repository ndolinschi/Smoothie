import SwiftUI

/// REF-4 styled task-row leading icon. A 36×36 rounded-rect tile with a
/// dashed circle inside, overlaid in the top-right by a small state-coloured
/// dot. The reference uses this to convey "task is alive / queued" without a
/// hard provider mark.
struct DashedCircleIcon: View {
    let dotColor: Color?
    var size: CGFloat = 36
    var stroke: Color = SmoothieColor.textTertiary
    var background: Color = SmoothieColor.bgCard

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background
            Circle()
                .strokeBorder(stroke,
                              style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .padding(7)
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(background, lineWidth: 1.5)
                    )
                    .offset(x: -2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: SmoothieMetrics.cornerSm))
    }
}
