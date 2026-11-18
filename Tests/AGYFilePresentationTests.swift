import Foundation

@main struct AGYFilePresentationTests {
    static func main() {
        precondition(AGYFilePresentation.label(scope: "workspace", folder: "资料", name: "合同 空格.pdf", directory: false) == "资料/合同 空格.pdf")
        precondition(AGYFilePresentation.label(scope: "workspace", folder: "项目", name: "src", directory: true) == "项目/src/")
        precondition(AGYFilePresentation.label(scope: "uploads", folder: "", name: "图片.png", directory: false) == "上传/图片.png")
        precondition(AGYFilePresentation.label(scope: "artifacts", folder: "", name: "结果.md", directory: false) == "产物/结果.md")
        precondition(AGYFilePresentation.opensMention(old: "分析 ", new: "分析 @"))
        precondition(!AGYFilePresentation.opensMention(old: "分析 @", new: "分析 @"))
        precondition(!AGYFilePresentation.opensMention(old: "", new: "abc@example.com"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        precondition(AGYFilePresentation.modifiedText(1_763_472_300, calendar: utc) == "2025-11-18 13:25")
        let ts2026 = DateComponents(calendar: utc, year: 2026, month: 11, day: 18, hour: 13, minute: 25).date!.timeIntervalSince1970
        precondition(AGYFilePresentation.modifiedText(ts2026, calendar: utc) == "2026-11-18 13:25")
        precondition(AGYFilePresentation.modifiedText(0, calendar: utc) == nil)
        precondition(AGYFilePresentation.modifiedText(-10, calendar: utc) == nil)
        precondition(AGYFilePresentation.metadataLine(directory: true, size: 0, modified: ts2026, calendar: utc) == "文件夹 · 2026-11-18 13:25")
        precondition(AGYFilePresentation.metadataLine(directory: false, size: 2048, modified: ts2026, calendar: utc).hasSuffix(" · 2026-11-18 13:25"))
        precondition(AGYFilePresentation.metadataLine(directory: true, size: 0, modified: 0, calendar: utc) == "文件夹")
        print("File and directory mention presentation passed")
    }
}
