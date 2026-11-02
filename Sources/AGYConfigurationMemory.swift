import Foundation

struct AGYConfigurationMemory: Codable, Equatable {
    var model: String
    var approvalMode: String
    var mode: String
    var workspace: String

    static func key(scope: String) -> String {
        "agy.configuration.v1." + Data(scope.utf8).base64EncodedString()
    }
    static func load(scope: String, defaults: UserDefaults = .standard) -> Self? {
        guard !scope.isEmpty, let data = defaults.data(forKey: key(scope: scope)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save(scope: String, defaults: UserDefaults = .standard) {
        guard !scope.isEmpty, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key(scope: scope))
    }
    func validated(models: [String], defaultModel: String, roots: [String]) -> Self {
        let fallback = models.contains(defaultModel) ? defaultModel : models.first ?? ""
        let path = URL(fileURLWithPath: workspace).standardizedFileURL.path
        let allowed = workspace.hasPrefix("/") && roots.contains { root in
            let base = URL(fileURLWithPath: root).standardizedFileURL.path
            return path == base || path.hasPrefix(base == "/" ? "/" : base + "/")
        }
        return Self(model: models.contains(model) ? model : fallback,
                    approvalMode: ["review", "turbo"].contains(approvalMode) ? approvalMode : "review",
                    mode: ["plan", "accept-edits"].contains(mode) ? mode : "plan",
                    workspace: allowed ? path : roots.first ?? "")
    }
}
