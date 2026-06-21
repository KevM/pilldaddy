import ActivityKit
import WidgetKit
import SwiftUI

struct PillReminderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PillReminderAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Circle().fill(accent(context.state.tier)).frame(width: 26, height: 26)
                        .overlay(Image(systemName: icon(context.state.tier)).font(.caption2).foregroundStyle(.white))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.batchName).font(.headline)
                        Text("\(context.attributes.medCount) meds · tap to log")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.scheduledDate...context.state.graceEndDate,
                         countsDown: false)
                        .font(.system(.title3, design: .rounded)).monospacedDigit()
                        .foregroundStyle(accent(context.state.tier))
                        .frame(maxWidth: 64)
                }
            } compactLeading: {
                Circle().fill(accent(context.state.tier)).frame(width: 12, height: 12)
            } compactTrailing: {
                Text(timerInterval: context.state.scheduledDate...context.state.graceEndDate,
                     countsDown: false)
                    .monospacedDigit().frame(maxWidth: 44)
                    .foregroundStyle(accent(context.state.tier))
            } minimal: {
                Circle().fill(accent(context.state.tier)).frame(width: 12, height: 12)
            }
            .widgetURL(URL(string: "pilldaddy://routine/\(context.attributes.batchID)"))
        }
    }

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<PillReminderAttributes>) -> some View {
        let tier = context.state.tier
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon(tier))
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(accent(tier), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(tier, name: context.attributes.batchName))
                        .font(.headline).foregroundStyle(.white)
                    Text("\(context.attributes.medCount) meds")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Text(timerInterval: context.state.scheduledDate...context.state.graceEndDate,
                     countsDown: false)
                    .font(.system(.title3, design: .rounded)).monospacedDigit()
                    .foregroundStyle(accent(tier))
            }
            ProgressView(timerInterval: context.state.scheduledDate...context.state.graceEndDate,
                         countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(accent(tier))
        }
        .padding(14)
        .widgetURL(URL(string: "pilldaddy://routine/\(context.attributes.batchID)"))
    }

    private func accent(_ tier: ReminderTier) -> Color {
        switch tier {
        case .calm: return Color(red: 0.23, green: 0.51, blue: 0.96)   // blue
        case .overdue: return Color(red: 0.96, green: 0.62, blue: 0.04) // amber
        case .urgent: return Color(red: 0.94, green: 0.27, blue: 0.27)  // red
        }
    }

    private func icon(_ tier: ReminderTier) -> String {
        switch tier {
        case .calm: return "pills.fill"
        case .overdue: return "clock.fill"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }

    private func title(_ tier: ReminderTier, name: String) -> String {
        switch tier {
        case .calm: return "\(name) is due"
        case .overdue: return "\(name) still due"
        case .urgent: return "\(name) overdue"
        }
    }
}
