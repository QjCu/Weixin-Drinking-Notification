import Foundation
import Security

struct AppError: LocalizedError {
    let message: String
    var statusCode: Int? = nil
    var errorDescription: String? { message }
}

enum TokenVault {
    private static func query(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "SipTime.account",
         kSecAttrAccount as String: server]
    }
    static func read(server: String) -> String? {
        var q = query(server)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String, server: String) throws {
        let q = query(server)
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let existing = SecItemUpdate(q as CFDictionary, values as CFDictionary)
        if existing == errSecItemNotFound {
            let status = SecItemAdd(q.merging(values) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw AppError(message: "无法安全保存账号，请重试（\(status)）") }
        } else if existing != errSecSuccess {
            throw AppError(message: "无法更新账号凭据（\(existing)）")
        }
    }
}

struct APIClient {
    let baseURL: URL
    let token: String?
    static func normalizedURL(_ string: String) throws -> URL {
        guard var parts = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              parts.host != nil, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else {
            throw AppError(message: "请填写服务器根地址，例如 http://192.168.1.10:8000")
        }
        #if !DEBUG
        guard scheme == "https" else { throw AppError(message: "正式版必须使用 HTTPS 服务器") }
        #endif
        parts.path = ""
        guard let url = parts.url else { throw AppError(message: "服务器地址无效") }
        return url
    }
    func request<Response: Decodable>(_ path: String, method: String = "GET",
                                       body: [String: Any]? = nil) async throws -> Response {
        let data = try await raw(path, method: method, body: body)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
    }
    func raw(_ path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppError(message: "服务器没有返回有效响应") }
        guard (200..<300).contains(response.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AppError(message: object?["detail"] as? String ?? "请求失败（\(response.statusCode)），请检查输入和账号",
                           statusCode: response.statusCode)
        }
        return data
    }
}
