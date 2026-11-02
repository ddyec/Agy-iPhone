import ActivityKit
import SwiftUI
import WidgetKit

@main struct AGYActivityWidgets: WidgetBundle {
    var body: some Widget { AGYTaskWidget() }
}
struct AGYTaskWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AGYActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image("AntigravityMark").resizable().scaledToFit().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(context.isStale ? "待同步" : context.state.label, systemImage: context.isStale ? "arrow.clockwise" : context.state.symbol)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        elapsed(context)
                    }
                    Text(context.state.title).font(.headline).lineLimit(1)
                    Text(context.isStale ? "打开 AGY 同步最新进展" : context.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(16)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(AGYActivityPolicy.link(session: context.attributes.sessionID, scope: context.attributes.scope))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("AntigravityMark").resizable().scaledToFit().frame(width: 28, height: 28)
                }
                DynamicIslandExpandedRegion(.trailing) { elapsed(context) }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.isStale ? "待同步" : context.state.label).font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.isStale ? "点按返回 AGY 同步" : context.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image("AntigravityMark").resizable().scaledToFit().frame(width: 20, height: 20)
            } compactTrailing: {
                Image(systemName: context.isStale ? "arrow.clockwise" : context.state.symbol).font(.caption)
            } minimal: {
                Image("AntigravityMark").resizable().scaledToFit()
            }
            .widgetURL(AGYActivityPolicy.link(session: context.attributes.sessionID, scope: context.attributes.scope))
        }
    }
    @ViewBuilder private func elapsed(_ context: ActivityViewContext<AGYActivityAttributes>) -> some View {
        if context.state.finished {
            Text(String(format: "%d:%02d", context.state.elapsed / 60, context.state.elapsed % 60)).monospacedDigit().font(.caption)
        } else if context.isStale || context.state.phase == "paused" {
            Text(context.state.updatedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
        } else {
            Text(context.attributes.startedAt, style: .timer).monospacedDigit().font(.caption).frame(maxWidth: 90)
        }
    }
}
