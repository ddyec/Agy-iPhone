import ActivityKit
import Foundation

struct AGYActivityAttributes: ActivityAttributes {
    typealias ContentState = AGYActivityState
    let sessionID: String
    let taskID: String
    let scope: String
    let startedAt: Date
}
