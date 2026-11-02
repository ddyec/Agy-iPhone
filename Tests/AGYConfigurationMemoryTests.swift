import Foundation

@main struct AGYConfigurationMemoryTests {
    static func main() throws {
        let suite = "AGYConfigurationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AGYConfigurationMemory(model: "gemini-high", approvalMode: "turbo", mode: "accept-edits", workspace: "/work/project")
        first.save(scope: "https://one#account-A", defaults: defaults)
        // Simulate a new store/process reading persisted defaults.
        let reopened = UserDefaults(suiteName: suite)!
        precondition(AGYConfigurationMemory.load(scope: "https://one#account-A", defaults: reopened) == first)
        precondition(AGYConfigurationMemory.load(scope: "https://one#account-B", defaults: reopened) == nil)
        precondition(AGYConfigurationMemory.load(scope: "https://two#account-A", defaults: reopened) == nil)
        precondition(first.validated(models: ["gemini-low", "gemini-high"], defaultModel: "gemini-low", roots: ["/work"]) == first)
        let unavailable = first.validated(models: ["claude"], defaultModel: "removed", roots: ["/other"])
        precondition(unavailable.model == "claude" && unavailable.workspace == "/other")
        precondition(unavailable.approvalMode == "turbo" && unavailable.mode == "accept-edits")
        for path in ["/workspace-other", "/work/../private", "relative"] {
            let invalid = AGYConfigurationMemory(model: "missing", approvalMode: "legacy", mode: "bad", workspace: path)
                .validated(models: ["default"], defaultModel: "default", roots: ["/work"])
            precondition(invalid.workspace == "/work" && invalid.model == "default")
            precondition(invalid.approvalMode == "review" && invalid.mode == "plan")
        }
        defaults.set(Data("broken".utf8), forKey: AGYConfigurationMemory.key(scope: "corrupt"))
        precondition(AGYConfigurationMemory.load(scope: "corrupt", defaults: defaults) == nil)
        print("Configuration persistence, scope isolation and fallback checks passed")
    }
}
