import ActivityKit
import Combine
import CryptoKit
import Foundation

@MainActor final class AGYLiveActivity: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "liveActivityEnabled"); if !enabled { clear() } }
    }
    @Published var previews: Bool {
        didSet { UserDefaults.standard.set(previews, forKey: "liveActivityPreviews") }
    }
    @Published private(set) var issue: String?
    var available: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    private enum Input { case session(AGYSession, String, Bool), pause, clear }
    private var needsClear = false
    private var pending: Input?
    private var worker: Task<Void, Never>?
    private var monitors: [String: Task<Void, Never>] = [:]
    private var dismissed = Set(UserDefaults.standard.stringArray(forKey: "dismissedLiveTasks") ?? [])
    init() {
        enabled = UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
        previews = UserDefaults.standard.bool(forKey: "liveActivityPreviews")
        for activity in Activity<AGYActivityAttributes>.activities { monitor(activity) }
    }
    static func scope(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func resumeSession(scope: String) -> String? {
        active().first(where: { $0.attributes.scope == scope })?.attributes.sessionID
    }
    func update(_ session: AGYSession, scope: String, foreground: Bool) { enqueue(.session(session, scope, foreground)) }
    func pause() { enqueue(.pause) }
    func clear() { needsClear = true; enqueue(.clear) }
    private func enqueue(_ input: Input) {
        pending = input
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while self.pending != nil || self.needsClear {
                if self.needsClear {
                    self.needsClear = false
                    await self.apply(.clear)
                }
                // Coalesce streamed tokens; ActivityKit only needs a short progress sample.
                try? await Task.sleep(for: .milliseconds(600))
                guard let latest = self.pending else { continue }
                self.pending = nil
                await self.apply(latest)
            }
            self.worker = nil
        }
    }
    private func taskKey(_ attributes: AGYActivityAttributes) -> String {
        attributes.scope + ":" + attributes.sessionID + ":" + attributes.taskID
    }
    private func monitor(_ activity: Activity<AGYActivityAttributes>) {
        guard monitors[activity.id] == nil else { return }
        monitors[activity.id] = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self else { return }
                if state == .dismissed {
                    self.dismissed.insert(self.taskKey(activity.attributes))
                    UserDefaults.standard.set(Array(self.dismissed.suffix(100)), forKey: "dismissedLiveTasks")
                    break
                }
                if state == .ended { break }
            }
            self?.monitors.removeValue(forKey: activity.id)
        }
    }
    private func active() -> [Activity<AGYActivityAttributes>] {
        Activity<AGYActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }
    private func pause(_ activity: Activity<AGYActivityAttributes>) async {
        var state = activity.content.state
        state.phase = "paused"; state.detail = "打开 AGY 同步最新进展"
        await activity.update(ActivityContent(state: state, staleDate: Date()))
    }
    private func apply(_ input: Input) async {
        if !enabled {
            for activity in Activity<AGYActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        switch input {
        case .clear:
            for activity in Activity<AGYActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        case .pause:
            for activity in active() { await pause(activity) }
        case .session(let session, let scope, let foreground):
            guard !scope.isEmpty else { return }
            // Account/server changes must remove old lock-screen content.
            for activity in Activity<AGYActivityAttributes>.activities where activity.attributes.scope != scope {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            guard let task = session.messages?.last(where: { $0.role == "user" }) else { return }
            let matching = active().first { $0.attributes.sessionID == session.id && $0.attributes.taskID == task.id }
            guard foreground else { for activity in active() { await pause(activity) }; return }
            guard session.running || matching != nil else {
                // Viewing an idle conversation does not finish another task.
                for activity in active() { await pause(activity) }
                return
            }
            let start = matching?.attributes.startedAt ?? Date(timeIntervalSince1970: min(Date().timeIntervalSince1970, session.modified))
            let message = session.messages?.last(where: { $0.role == "assistant" })
            let progress = message?.steps?.last?.text ?? message?.text ?? ""
            let state = AGYActivityPolicy.state(running: session.running, approvalCount: session.approvals?.count ?? 0,
                                                error: session.error, title: session.name, progress: progress,
                                                previews: previews, startedAt: start, now: Date())
            let content = ActivityContent(state: state, staleDate: session.running ? Date().addingTimeInterval(45) : nil)
            if let matching {
                if session.running { await matching.update(content) }
                else { await matching.end(content, dismissalPolicy: .after(Date().addingTimeInterval(90))) }
            } else if session.running, available {
                for activity in Activity<AGYActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
                do {
                    let attributes = AGYActivityAttributes(sessionID: session.id, taskID: task.id, scope: scope, startedAt: start)
                    guard !dismissed.contains(taskKey(attributes)) else { return }
                    let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                    monitor(activity)
                    issue = nil
                } catch { issue = "无法启用实时活动：" + error.localizedDescription }
            }
        }
    }
}
