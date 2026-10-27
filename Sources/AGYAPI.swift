import Foundation
import UIKit

struct AGYModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}
struct AGYTool: Codable, Identifiable {
    let id: String
    let name: String
    let state: String
    let parameters: WireValue
    let output: String
}
struct AGYMessage: Codable, Identifiable {
    let id: String
    let role: String
    let text: String
    var tools: [AGYTool]?
    var rendered: ChatMessage { ChatMessage(id: id, value: .object(["role": .string(role), "content": .string(text)])) }
}
struct AGYSession: Codable, Identifiable {
    let id: String
    var name: String
    let cwd: String
    let model: String
    let mode: String
    let modified: Double
    let running: Bool
    let conversationID: String
    let error: String
    let revision: Int
    var messages: [AGYMessage]?
}
struct AGYStatus: Decodable {
    let name: String
    let version: Int
    let roots: [String]
    let defaultModel: String
}
struct AGYModels: Decodable { let models: [AGYModel] }
struct AGYSessions: Decodable { let sessions: [AGYSession] }
struct AGYCredentials: Codable {
    let url: URL
    let token: String
    static func validated(_ rawURL: String, token: String) throws -> Self {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, ["", "/"].contains(url.path), token.count >= 32,
              !token.contains("\n"), !token.contains("\r") else { throw AGYError.message("请输入 HTTPS 服务器地址和完整连接密钥。") }
        return Self(url: url, token: token)
    }
}
enum AGYError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
final class AGYRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor final class AGYAPI {
    var credentials: AGYCredentials
    private let policy = AGYRedirectPolicy()
    private let session: URLSession
    init(credentials: AGYCredentials) {
        self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 65
        config.timeoutIntervalForResource = 120
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: policy, delegateQueue: nil)
    }
    func request(_ path: String, method: String = "GET", body: WireValue? = nil) throws -> URLRequest {
        var request = URLRequest(url: credentials.url.appendingPathComponent("v1").appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Match the mobile client identity used by the existing Pi app so the
        // origin's Browser Integrity Check accepts native API requests.
        let os = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS \(os) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 AGY-iPhone/1.0.1", forHTTPHeaderField: "User-Agent")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    func validate(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { throw AGYError.message("服务器响应无效") }
        guard (200..<300).contains(http.statusCode) else {
            let text = data.flatMap { try? JSONDecoder().decode(WireValue.self, from: $0) }?["error"].string ?? ""
            throw AGYError.message(http.statusCode == 401 ? "连接密钥已失效，请重新连接。" : text.isEmpty ? "服务器返回 HTTP \(http.statusCode)" : text)
        }
    }
    func json<T: Decodable>(_ path: String, method: String = "GET", body: WireValue? = nil) async throws -> T {
        let (data, response) = try await session.data(for: request(path, method: method, body: body))
        try validate(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }
    func events(_ id: String, receive: @escaping (AGYSession) -> Void) async throws {
        var req = try request("sessions/\(id)/events")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: req)
        try validate(response)
        guard (response as? HTTPURLResponse)?.mimeType == "text/event-stream" else { throw AGYError.message("服务器没有返回事件流") }
        // Preserve original delimiters; Foundation's lines adapter can discard SSE blank lines.
        var line: [UInt8] = [], parser = SSEParser(), previousCR = false
        for try await byte in bytes {
            try Task.checkCancellation()
            if previousCR { previousCR = false; if byte == 10 { continue } }
            if byte == 10 || byte == 13 {
                previousCR = byte == 13
                if let data = try parser.consume(String(decoding: line, as: UTF8.self)) {
                    receive(try JSONDecoder().decode(AGYSession.self, from: Data(data.utf8)))
                }
                line.removeAll(keepingCapacity: true)
            } else {
                guard line.count < 20 * 1024 * 1024 else { throw AGYError.message("事件内容过大") }
                line.append(byte)
            }
        }
    }
    func invalidate() { session.invalidateAndCancel() }
}
