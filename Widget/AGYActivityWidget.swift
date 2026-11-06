import ActivityKit
import SwiftUI
import WidgetKit

@main struct AGYActivityWidgets: WidgetBundle {
    var body: some Widget { AGYTaskWidget() }
}
struct AGYTaskWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AGYActivityAttributes.self) { context in
            AGYActivityCard(context: context).padding(16)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(AGYActivityPolicy.link(session: context.attributes.sessionID, scope: context.attributes.scope))
        } dynamicIsland: { context in
            DynamicIsland {
                // Keep the logo, status, timer and title in ONE aligned layout.
                // Independent center/trailing regions drift around the camera.
                DynamicIslandExpandedRegion(.bottom) {
                    AGYActivityCard(context: context).padding(.horizontal, 4).padding(.vertical, 6)
                }
            } compactLeading: {
                Image("AntigravityMark").resizable().scaledToFit().frame(width: 20, height: 20)
            } compactTrailing: {
                if context.state.phase == "review", !context.isStale {
                    Text("审批").font(.caption2)
                } else { AGYActivityElapsed(context: context).frame(width: 48, alignment: .trailing) }
            } minimal: {
                Image("AntigravityMark").resizable().scaledToFit().frame(width: 20, height: 20)
            }
            .widgetURL(AGYActivityPolicy.link(session: context.attributes.sessionID, scope: context.attributes.scope))
        }
    }
}
private struct AGYActivityCard: View {
    let context: ActivityViewContext<AGYActivityAttributes>
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("AntigravityMark").resizable().scaledToFit().frame(width: 30, height: 30).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.isStale ? "待同步" : context.state.label).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    AGYActivityElapsed(context: context).frame(width: 65, alignment: .trailing)
                }
                Text(context.state.title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if context.isStale {
                    Text("点按返回 AGY 同步").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if !context.state.detail.isEmpty, context.state.detail != "点按返回会话" {
                    Text(context.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct AGYActivityElapsed: View {
    let context: ActivityViewContext<AGYActivityAttributes>
    var body: some View {
        Group {
            if context.state.finished {
                Text(String(format: "%d:%02d", context.state.elapsed / 60, context.state.elapsed % 60))
            } else if context.isStale || context.state.phase == "paused" {
                Text("待同步")
            } else {
                Text(context.attributes.startedAt, style: .timer)
            }
        }.font(.caption.monospacedDigit()).multilineTextAlignment(.trailing)
    }
}
