import Foundation

/// Async Cloudflare v4 client: envelope decode, auth header injection,
/// Retry-After mapping, local throttle, raw/multipart bodies.
nonisolated final class CloudflareClient: Sendable, @unchecked Sendable {
    static let apiBase = URL(string: "https://api.cloudflare.com/client/v4")!
    static let graphqlURL = URL(string: "https://api.cloudflare.com/client/v4/graphql")!

    private let auth: AuthConfig
    private let session: URLSession
    private let throttle: RateLimitTracker

    init(auth: AuthConfig, session: URLSession = .shared, throttle: RateLimitTracker = RateLimitTracker()) {
        self.auth = auth
        self.session = session
        self.throttle = throttle
    }

    /// Remaining local request budget (observable "throttled" signal).
    var remainingBudget: Int {
        get async { await throttle.remaining }
    }

    // MARK: - Envelope requests

    /// Sends a request and decodes the `CloudflareResponse<T>` envelope, throwing on failure.
    func send<T: Decodable & Sendable>(_ request: CloudflareRequest) async throws -> CloudflareResponse<T> {
        let (data, httpResponse) = try await perform(request)
        let decoded = try Self.decodeEnvelope(T.self, from: data)
        try Self.validate(decoded, httpResponse: httpResponse)
        return decoded
    }

    /// Sends a request whose result is a JSON array; returns the elements.
    func sendList<T: Decodable & Sendable>(_ request: CloudflareRequest) async throws -> (items: [T], info: ResultInfo?) {
        let response: CloudflareResponse<[T]> = try await send(request)
        return (response.result ?? [], response.resultInfo)
    }

    /// Sends a request whose result is a single object; fails on null result.
    func sendObject<T: Decodable & Sendable>(_ request: CloudflareRequest) async throws -> T {
        let response: CloudflareResponse<T> = try await send(request)
        guard let result = response.result else { throw CloudflareError.emptyResult }
        return result
    }

    // MARK: - Raw requests (DNS export text, KV value read)

    /// Performs a request and returns the raw body bytes without envelope decoding.
    func sendRaw(_ request: CloudflareRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        try await perform(request)
    }

    // MARK: - GraphQL

    /// Runs a GraphQL request (analytics). Decodes the envelope with result = data.
    func graphql<Response: Decodable & Sendable>(query: String, variables: [String: String] = [:]) async throws -> Response {
        let body = try JSONEncoder().encode(GraphQLQuery(query: query, variables: variables))
        var urlRequest = URLRequest(url: Self.graphqlURL)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &urlRequest)

        try await throttle.acquire()
        let (data, httpResponse) = try await execute(urlRequest)
        try Self.checkHTTP(httpResponse, data: data)
        do {
            return try JSONDecoder().decode(GraphQLEnvelope<Response>.self, from: data).data
        } catch {
            throw CloudflareError.decoding(error)
        }
    }

    private struct GraphQLEnvelope<T: Decodable>: Decodable {
        let data: T
        let errors: [GraphError]?
        struct GraphError: Decodable { let message: String }
    }

    private struct GraphQLQuery: Encodable {
        let query: String
        let variables: [String: String]
    }

    // MARK: - Internals

    private func perform(_ request: CloudflareRequest) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = try buildURLRequest(request)
        applyAuth(to: &urlRequest)
        try await throttle.acquire()
        let (data, httpResponse) = try await execute(urlRequest)
        try Self.checkHTTP(httpResponse, data: data)
        return (data, httpResponse)
    }

    func buildURLRequest(_ request: CloudflareRequest) throws -> URLRequest {
        var components = URLComponents(url: Self.apiBase, resolvingAgainstBaseURL: true)!
        components.path += request.path
        if !request.query.isEmpty {
            components.queryItems = request.query
        }
        guard let url = components.url else {
            throw CloudflareError.decoding(URLError(.badURL))
        }
        var urlRequest = URLRequest(url: url, timeoutInterval: 30)
        urlRequest.httpMethod = request.method.rawValue
        switch request.body {
        case .none:
            break
        case let .json(data):
            urlRequest.httpBody = data
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case let .raw(data, contentType):
            urlRequest.httpBody = data
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        case let .multipart(multipart):
            urlRequest.httpBody = multipart.encoded()
            urlRequest.setValue(multipart.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }

    private func applyAuth(to urlRequest: inout URLRequest) {
        for (name, value) in auth.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
    }

    private func execute(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudflareError.network(URLError(.badServerResponse))
            }
            return (data, httpResponse)
        } catch let error as URLError {
            throw CloudflareError.network(error)
        } catch {
            throw error
        }
    }

    private static func checkHTTP(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw CloudflareError.unauthorized
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) } ?? 60
            throw CloudflareError.rateLimited(retryAfter: retryAfter)
        default:
            // Prefer the envelope's error detail when present.
            if let decoded = try? decodeEnvelope(CloudflareError.APIError.self, from: data),
               let first = decoded.errors.first {
                throw CloudflareError.api(code: first.code, message: first.message, errors: decoded.errors)
            }
            throw CloudflareError.http(status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) })
        }
    }

    private static func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> CloudflareResponse<T> {
        do {
            return try JSONDecoder().decode(CloudflareResponse<T>.self, from: data)
        } catch {
            throw CloudflareError.decoding(error)
        }
    }

    private static func validate<T>(_ response: CloudflareResponse<T>, httpResponse: HTTPURLResponse) throws {
        guard response.success else {
            let first = response.errors.first
            throw CloudflareError.api(
                code: first?.code ?? httpResponse.statusCode,
                message: first?.message ?? "Cloudflare API error",
                errors: response.errors
            )
        }
    }
}
