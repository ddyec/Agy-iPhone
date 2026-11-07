import Foundation

enum AGYActivityRefreshPolicy {
    static let foregroundInterval: Double = 8
    static let backgroundInterval: Double = 5
    static let backgroundBudget: Double = 25
    static let staleInterval: Double = 90
    static func shouldSynchronize(foreground: Bool, hasBackgroundTime: Bool, running: Bool) -> Bool {
        running && (foreground || hasBackgroundTime)
    }
}
