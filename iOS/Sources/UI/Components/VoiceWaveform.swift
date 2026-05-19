import SwiftUI

/// Amplitude-driven waveform shown inside the composer while the user is
/// dictating. Five rounded vertical bars whose height tracks `level` (0...1)
/// with a per-bar phase offset for organic motion. Drives its animation from
/// a `TimelineView(.animation)` so SwiftUI redraws ~60 Hz without needing a
/// timer of its own.
struct VoiceWaveform: View {
    let level: Float
    var barCount: Int = 5
    var color: Color = .white

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let spacing: CGFloat = 5
                let barWidth: CGFloat = 4
                let totalWidth = barWidth * CGFloat(barCount) + spacing * CGFloat(barCount - 1)
                let originX = (size.width - totalWidth) / 2
                let midY = size.height / 2
                let amplitude = CGFloat(max(0.05, min(1, level)))

                for i in 0..<barCount {
                    let phase = now * 7 + Double(i) * 0.55
                    let wave = (sin(phase) + 1) / 2
                    let normalized = (0.2 + amplitude * 0.8) * CGFloat(0.4 + wave * 0.6)
                    let height = max(barWidth, size.height * normalized)
                    let x = originX + CGFloat(i) * (barWidth + spacing)
                    let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                    let path = Path(roundedRect: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
                    context.fill(path, with: .color(color.opacity(0.85)))
                }
            }
        }
    }
}
