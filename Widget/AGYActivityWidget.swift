import ActivityKit
import SwiftUI
import WidgetKit

@main struct AGYActivityWidgets: WidgetBundle {
    var body: some Widget { AGYTaskWidget() }
}
struct AGYTaskWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AGYActivityAttributes.self) { context in
            AGYActivityCard(context: context).padding(.horizontal, 12).padding(.vertical, 10)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
                .contentMargins(.top, 4, for: .expanded)
            .contentMargins(.bottom, 6, for: .expanded)
            .widgetURL(AGYActivityPolicy.link(session: context.attributes.sessionID, scope: context.attributes.scope))
        } dynamicIsland: { context in
            DynamicIsland {
                // Use the space BESIDE the camera instead of reserving an
                // empty top row above a full bottom-region card.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image("AntigravityMark").resizable().scaledToFit().frame(width: 18, height: 18)
                        Text(context.isStale ? "待同步" : context.state.label)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(height: 20, alignment: .center)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AGYActivityElapsed(context: context, compact: true)
                        .frame(width: 46, height: 20, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.title).font(.subheadline.weight(.semibold))
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image("AntigravityMark").resizable().scaledToFit().frame(width: 16, height: 16)
            } compactTrailing: {
                if context.state.phase == "review", !context.isStale {
                    Text("审批").font(.caption2)
                } else { AGYActivityElapsed(context: context, compact: true).frame(width: 42, alignment: .trailing) }
            } minimal: {
                Image("AntigravityMark").resizable().scaledToFit().frame(width: 16, height: 16)
            }
            .widgetURL(AGYActivityPolicy.link(session: context.attributes.sessionID, scope: context.attributes.scope))
        }
    }
}
private struct AGYActivityCard: View {
    let context: ActivityViewContext<AGYActivityAttributes>
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image("AntigravityMark").resizable().scaledToFit().frame(width: 24, height: 24).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.isStale ? "待同步" : context.state.label).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    AGYActivityElapsed(context: context).frame(width: 65, alignment: .trailing)
                }
                Text(context.state.title).font(.subheadline.weight(.semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if context.isStale {
                    Text("点按返回 AGY 同步").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if !context.state.detail.isEmpty, context.state.detail != "点按返回会话" {
                    Text(context.state.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct AGYActivityElapsed: View {
    let context: ActivityViewContext<AGYActivityAttributes>
    var compact = false
    var body: some View {
        Group {
            if context.state.finished {
                Text(String(format: "%d:%02d", context.state.elapsed / 60, context.state.elapsed % 60))
            } else if context.isStale || context.state.phase == "paused" {
                Text("待同步")
            } else {
                Text(context.attributes.startedAt, style: .timer)
            }
        }.font(compact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
            .minimumScaleFactor(0.8).lineLimit(1).multilineTextAlignment(.trailing)
    }
}
