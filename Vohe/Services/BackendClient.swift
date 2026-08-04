import Foundation

/// One dictionary as listed in the backend catalog.
struct RemoteDictionarySummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let language1: String
    let language2: String
    let version: Int
    let wordCount: Int
}

struct RemoteWord: Decodable, Hashable {
    let word: String
    let translation: String
}

/// One dictionary with every approved word in it.
struct RemoteDictionary: Decodable {
    let id: Int
    let name: String
    let language1: String
    let language2: String
    let version: Int
    let entries: [RemoteWord]
}

/// What the backend did with the words we sent for review.
struct SubmissionReceipt: Decodable {
    struct Rejected: Decodable {
        let word: String
        let reason: String
    }
    let accepted: Int
    let alreadyPending: Int
    let invalid: [Rejected]
}

enum BackendError: LocalizedError {
    case notConfigured
    case unauthorized
    case unreachable
    case notFound
    case server(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add the dictionary server address and access token first."
        case .unauthorized:
            return "The server rejected the access token."
        case .unreachable:
            return "Can't reach the dictionary server. Your decks on this device are unaffected."
        case .notFound:
            return "That dictionary no longer exists on the server."
        case .server(let message):
            return message
        case .malformedResponse:
            return "The server sent something this app can't read."
        }
    }
}

/// Read the catalog, read one dictionary, propose words. Nothing else — the
/// backend is the only place where a proposed word becomes part of a dictionary.
struct BackendClient {
    let settings: BackendSettings
    var session: URLSession = .shared

    func catalog() async throws -> [RemoteDictionarySummary] {
        struct Payload: Decodable { let decks: [RemoteDictionarySummary] }
        let data = try await get(path: "/api/decks")
        return try decode(Payload.self, from: data).decks
    }

    func dictionary(id: Int) async throws -> RemoteDictionary {
        let data = try await get(path: "/api/decks/\(id)")
        return try decode(RemoteDictionary.self, from: data)
    }

    /// Sends words for review. They join the dictionary only once approved on
    /// the backend, so a successful call means "queued", not "published".
    func submit(_ words: [RemoteWord], toDictionary id: Int) async throws -> SubmissionReceipt {
        let body = ["entries": words.map { ["word": $0.word, "translation": $0.translation] }]
        let data = try await send(
            path: "/api/decks/\(id)/submissions",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        return try decode(SubmissionReceipt.self, from: data)
    }

    // MARK: - Plumbing

    private func get(path: String) async throws -> Data {
        try await send(path: path, method: "GET", body: nil)
    }

    private func send(path: String, method: String, body: Data?) async throws -> Data {
        guard settings.isConfigured, let root = settings.url else {
            throw BackendError.notConfigured
        }
        guard let url = URL(string: root.absoluteString + path) else {
            throw BackendError.notConfigured
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.unreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw BackendError.malformedResponse
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw BackendError.unauthorized
        case 404:
            throw BackendError.notFound
        default:
            throw BackendError.server(Self.message(from: data, status: http.statusCode))
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw BackendError.malformedResponse
        }
    }

    private static func message(from data: Data, status: Int) -> String {
        struct Payload: Decodable { let error: String }
        if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            return payload.error
        }
        return "The server returned an error (\(status))."
    }
}
