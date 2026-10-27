import SwiftUI

struct NativePiLogo: View {
    var size: CGFloat = 48
    var body: some View {
        Image(systemName: "a.circle.fill").resizable().scaledToFit()
            .foregroundStyle(LinearGradient(colors: [.cyan, .blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size).accessibilityLabel("AGY")
    }
}
struct HistorySwipeExclusions: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value.append(contentsOf: nextValue()) }
}
extension View {
    func reservesHorizontalSwipe() -> some View {
        background(GeometryReader { geometry in Color.clear.preference(key: HistorySwipeExclusions.self, value: [geometry.frame(in: .global)]) })
    }
}
