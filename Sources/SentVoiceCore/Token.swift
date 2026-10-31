import Foundation

/// A voice token the app's backend minted, exchanged with Sent for the credential the client registers with.
public struct VoiceToken: Sendable, Equatable {
    /// The voice token as the token provider returned it.
    public let token: String
    /// The credential the provider adapter registers with. Never shown to the app.
    public let credential: String
    /// The user the token names.
    public let identity: String
    /// The Sent number the user is bound to, when the token carries one.
    public let number: String?
    /// The prefix that qualifies user identities and conference names for the provider.
    public let prefix: String
    public let issuedAt: Date
    public let expiresAt: Date

    public init(token: String, credential: String, identity: String, number: String?, prefix: String, issuedAt: Date, expiresAt: Date) {
        self.token = token
        self.credential = credential
        self.identity = identity
        self.number = number
        self.prefix = prefix
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    public var lifetime: TimeInterval { expiresAt.timeIntervalSince(issuedAt) }
}

/// Fetches a voice token from the app and exchanges it with Sent, with the retry timing the contract fixes.
public enum TokenExchange {
    static let exchangePath = "/v3/voice/tokens/exchange"

    public static func fetch(
        tokenProvider: @Sendable () async throws -> String,
        baseURL: URL = SentAPI.defaultBaseURL,
        http: HTTPClient
    ) async throws -> VoiceToken {
        let token: String
        do {
            token = try await tokenProvider()
        } catch {
            throw SentVoiceError(code: .network, message: "The token provider failed to fetch a voice token.")
        }
        guard !token.isEmpty else { throw SentVoiceError(code: .tokenInvalid) }

        // No body, so no Content-Type: the API refuses one on a request without a body.
        var request = URLRequest(url: SentAPI.url(baseURL, path: exchangePath))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch {
            throw SentVoiceError(code: .network, message: "Sent could not be reached to exchange the voice token.")
        }
        if response.statusCode == 401 || response.statusCode == 403 { throw SentVoiceError(code: .tokenInvalid) }
        guard (200..<300).contains(response.statusCode) else {
            throw SentVoiceError(code: .network, message: "Sent could not exchange the voice token (HTTP \(response.statusCode)).")
        }
        return try read(token: token, body: data)
    }

    /// Reads the exchange response: `{ "data": { credential, identity, number?, prefix, issued_at, expires_at } }`.
    public static func read(token: String, body: Data) throws -> VoiceToken {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let data = json?["data"] as? [String: Any] ?? [:]
        guard
            let credential = data["credential"] as? String, !credential.isEmpty,
            let identity = data["identity"] as? String, !identity.isEmpty,
            let prefix = data["prefix"] as? String, !prefix.isEmpty,
            let issuedAt = (data["issued_at"] as? String).flatMap(parseDate),
            let expiresAt = (data["expires_at"] as? String).flatMap(parseDate),
            expiresAt > issuedAt
        else {
            throw SentVoiceError(code: .tokenInvalid, message: "Sent answered the token exchange with an unexpected body.")
        }
        let number = (data["number"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return VoiceToken(token: token, credential: credential, identity: identity, number: number, prefix: prefix, issuedAt: issuedAt, expiresAt: expiresAt)
    }

    /// How long after the token was issued it is refreshed: the contract's share of its lifetime, at least the
    /// margin before it expires, and never before half its lifetime.
    public static func refreshDelay(for token: VoiceToken) -> TimeInterval {
        let lifetime = token.lifetime
        return max(min(lifetime * TokenTiming.refreshShare, lifetime - TokenTiming.refreshMargin), lifetime / 2)
    }

    /// The wait before retry number `retry` (0-based) of a failed fetch, doubling up to the maximum, with jitter.
    public static func retryDelay(retry: Int, random: () -> Double = { Double.random(in: 0..<1) }) -> TimeInterval {
        min(TokenTiming.initialRetryDelay * pow(2, Double(retry)), TokenTiming.maxRetryDelay) * jitter(random)
    }

    /// The wait between fetch attempts while the client is offline, with jitter.
    public static func offlineRetryDelay(random: () -> Double = { Double.random(in: 0..<1) }) -> TimeInterval {
        TokenTiming.offlineRetryInterval * jitter(random)
    }

    static func jitter(_ random: () -> Double) -> Double { 1 - random() * 0.25 }

    static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: text)
    }
}
