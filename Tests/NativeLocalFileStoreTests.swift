import Foundation

@main struct NativeLocalFileStoreTests {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let sourceFolder = root.appendingPathComponent("temporary-network")
        try manager.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let original = sourceFolder.appendingPathComponent("response.tmp")
        let bytes = Data([0, 255, 10, 195, 0, 1])
        try bytes.write(to: original)
        let downloads = root.appendingPathComponent("手机本机下载")
        let first = try NativeLocalFileStore.persist(original, name: "中文 空格.bin", folder: downloads)
        let duplicate = try NativeLocalFileStore.persist(original, name: "中文 空格.bin", folder: downloads)
        precondition(first.lastPathComponent == "中文 空格.bin")
        precondition(duplicate.lastPathComponent == "中文 空格 (2).bin")
        try manager.removeItem(at: sourceFolder)
        let retainedBytes = try Data(contentsOf: first)
        precondition(retainedBytes == bytes, "Removing the URLSession temporary file must not remove the local download")
        let localFiles = try NativeLocalFileStore.list(folder: downloads)
        precondition(localFiles.count == 2)
        let exportFolder = root.appendingPathComponent("用户选择的文件夹")
        try manager.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        let exported = try NativeLocalFileStore.export(first, to: exportFolder)
        let exportedBytes = try Data(contentsOf: exported)
        precondition(exportedBytes == bytes && exported.deletingLastPathComponent().resolvingSymlinksInPath().path == exportFolder.resolvingSymlinksInPath().path)
        let again = try NativeLocalFileStore.export(first, to: exportFolder)
        precondition(again.lastPathComponent == "中文 空格 (2).bin")
        let firstExportBytes = try Data(contentsOf: exported)
        precondition(firstExportBytes == bytes, "Saving again must not overwrite the existing file")
        do {
            _ = try NativeLocalFileStore.export(root.appendingPathComponent("missing"), to: exportFolder)
            preconditionFailure("Missing source must report an error")
        } catch { }
        let entries = try manager.contentsOfDirectory(at: exportFolder, includingPropertiesForKeys: nil)
        precondition(entries.count == 2 && !entries.contains { $0.pathExtension == "partial" })
        print("Persistent local downloads, selected-folder export, binary integrity and collision checks passed")
    }
}
