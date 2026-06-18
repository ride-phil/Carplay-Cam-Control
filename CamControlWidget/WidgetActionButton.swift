import SwiftUI
import AppIntents

/// A widget-safe button with a real visible background and a full-width tap
/// target. System button styles (.bordered, .borderedProminent) render
/// inconsistently inside WidgetKit, so the background/shape is drawn by hand.
struct WidgetActionButton<I: AppIntent>: View {
    let title: String
    let icon: String
    let color: Color
    let intent: I
    var isDisabled: Bool = false

    var body: some View {
        Button(intent: intent) {
            Label(title, systemImage: icon)
                .font(.caption2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(color.opacity(isDisabled ? 0.08 : 0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(isDisabled ? color.opacity(0.4) : color)
        .disabled(isDisabled)
    }
}
