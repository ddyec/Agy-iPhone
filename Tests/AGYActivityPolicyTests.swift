import Foundation

@main struct AGYActivityPolicyTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1000), start = Date(timeIntervalSince1970: 940)
        func state(_ running: Bool = true, _ approvals: Int = 0, _ error: String = "", previews: Bool = false) -> AGYActivityState {
            AGYActivityPolicy.state(running: running, approvalCount: approvals, error: error, title: "私密项目", progress: "正在检查\n多行进展", previews: previews, startedAt: start, now: now)
        }
        precondition(state().phase == "running" && state().elapsed == 60)
        precondition(state().title == "AGY 任务" && !state().detail.contains("检查"))
        precondition(state(true, 1).phase == "review" && state(true, 1).detail.contains("审批"))
        precondition(state(false).finished && state(false).phase == "done")
        precondition(state(false, 0, "失败").phase == "failed")
        precondition(state(false, 0, "用户停止").phase == "stopped")
        precondition(state(previews: true).title == "私密项目")
        precondition(state(previews: true).detail == "正在检查 多行进展")
        precondition(AGYActivityPolicy.excerpt(String(repeating: "字", count: 1000)).count == 120)
        let future = AGYActivityPolicy.state(running: true, approvalCount: 0, error: "", title: "", progress: "", previews: false, startedAt: now.addingTimeInterval(30), now: now)
        precondition(future.elapsed == 0)
        let id = UUID().uuidString.lowercased()
        let link = AGYActivityPolicy.link(session: id, scope: "account-A")!
        precondition(AGYActivityPolicy.session(from: link, scope: "account-A") == id)
        precondition(AGYActivityPolicy.session(from: link, scope: "account-B") == nil)
        precondition(AGYActivityPolicy.link(session: "../bad", scope: "account-A") == nil)
        precondition(AGYActivityPolicy.session(from: URL(string: "agy://session/\(id)?scope=account-A&scope=account-A")!, scope: "account-A") == nil)
        let encoded = try JSONEncoder().encode(state(previews: true))
        precondition(encoded.count < 4096)
        precondition(AGYActivityRefreshPolicy.shouldSynchronize(foreground: true, hasBackgroundTime: false, running: true))
        precondition(AGYActivityRefreshPolicy.shouldSynchronize(foreground: false, hasBackgroundTime: true, running: true))
        precondition(!AGYActivityRefreshPolicy.shouldSynchronize(foreground: false, hasBackgroundTime: false, running: true))
        precondition(!AGYActivityRefreshPolicy.shouldSynchronize(foreground: true, hasBackgroundTime: true, running: false))
        print("Live Activity state, privacy, payload bounds and deep-link checks passed")
    }
}
