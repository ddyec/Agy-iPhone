import Foundation

enum NativeLocalFileError: LocalizedError {
    case missingSource, missingDestination, incompleteCopy
    var errorDescription: String? {
        switch self {
        case .missingSource: return "本地下载文件不存在，请重新下载后再保存。"
        case .missingDestination: return "没有选择保存文件夹，文件尚未另存。"
        case .incompleteCopy: return "保存后的文件校验失败，请重新选择文件夹保存。"
        }
    }
}
enum NativeLocalFileStore {
    static var downloads: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("下载", isDirectory: true)
    }
    static func persist(_ source: URL, name: String, folder: URL = downloads) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try copyVerified(source, name: name, folder: folder)
    }
    static func export(_ source: URL, to folder: URL) throws -> URL {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<URL, Error>?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: .forMerging, error: &coordinationError) { writable in
            result = Result { try copyVerified(source, name: source.lastPathComponent, folder: writable) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw NativeLocalFileError.missingDestination }
        return try result.get()
    }
    private static func copyVerified(_ source: URL, name: String, folder: URL) throws -> URL {
        let manager = FileManager.default
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let expected = values.fileSize else { throw NativeLocalFileError.missingSource }
        let leaf = (name as NSString).lastPathComponent
        let clean = leaf.isEmpty || [".", ".."].contains(leaf) ? "下载文件" : leaf
        let staging = folder.appendingPathComponent(".agy-" + UUID().uuidString + ".partial")
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: source, to: staging)
        let metadata = try staging.resourceValues(forKeys: [.fileSizeKey])
        guard metadata.fileSize == expected else { throw NativeLocalFileError.incompleteCopy }
        let ext = (clean as NSString).pathExtension
        let stem = (clean as NSString).deletingPathExtension
        for index in 1...10000 {
            let filename = index == 1 ? clean : stem + " (\(index))" + (ext.isEmpty ? "" : "." + ext)
            let destination = folder.appendingPathComponent(filename)
            do {
                try manager.moveItem(at: staging, to: destination)
                guard try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize == expected else { throw NativeLocalFileError.incompleteCopy }
                #if os(iOS)
                try? manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
                #endif
                return destination
            } catch {
                if manager.fileExists(atPath: staging.path), manager.fileExists(atPath: destination.path) { continue }
                throw error
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
    static func list(folder: URL = downloads) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
    }
}
