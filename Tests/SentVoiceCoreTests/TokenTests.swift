import Foundation
import XCTest
@testable import SentVoiceCore

final class TokenTests: XCTestCase {
    func testExchangePostsTheVoiceTokenAsBearerWithNoBody() async throws {
        let http = FakeHTTP([FakeHTTP.ok(exchangeBody)])
        let token = try await TokenExchange.fetch(tokenProvider: { "voice.token" }, baseURL: URL(string: "https://api.example.test/")!, http: http)
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/v3/voice/tokens/exchange")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer voice.token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(token.credential, "eyJ.credential")
        XCTAssertEqual(token.identity, "alice")
        XCTAssertEqual(token.number, "+15555550100")
        XCTAssertEqual(token.prefix, "acme_")
        XCTAssertEqual(token.lifetime, 3600)
    }

    func testAFailingProviderIsANetworkError() async {
        let http = FakeHTTP([])
        await XCTAssertThrowsCode(.network) {
            _ = try await TokenExchange.fetch(tokenProvider: { throw Unreachable() }, http: http)
        }
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testAnEmptyTokenIsInvalid() async {
        await XCTAssertThrowsCode(.tokenInvalid) {
            _ = try await TokenExchange.fetch(tokenProvider: { "" }, http: FakeHTTP([]))
        }
    }

    func testUnauthorizedIsInvalidAndOtherFailuresAreNetwork() async {
        await XCTAssertThrowsCode(.tokenInvalid) {
            _ = try await TokenExchange.fetch(tokenProvider: { "t" }, http: FakeHTTP([FakeHTTP.ok("{}", status: 401)]))
        }
        await XCTAssertThrowsCode(.network) {
            _ = try await TokenExchange.fetch(tokenProvider: { "t" }, http: FakeHTTP([FakeHTTP.ok("{}", status: 503)]))
        }
        await XCTAssertThrowsCode(.network) {
            _ = try await TokenExchange.fetch(tokenProvider: { "t" }, http: FakeHTTP([.failure(Unreachable())]))
        }
    }

    func testAnUnexpectedBodyIsInvalid() async {
        await XCTAssertThrowsCode(.tokenInvalid) {
            _ = try await TokenExchange.fetch(tokenProvider: { "t" }, http: FakeHTTP([FakeHTTP.ok(#"{"data":{"credential":"c"}}"#)]))
        }
        let swapped = exchangeBody.replacingOccurrences(of: "11:00:00", with: "09:00:00")
        await XCTAssertThrowsCode(.tokenInvalid) {
            _ = try await TokenExchange.fetch(tokenProvider: { "t" }, http: FakeHTTP([FakeHTTP.ok(swapped)]))
        }
    }

    func testRefreshDelayFollowsTheContract() {
        func token(lifetime: TimeInterval) -> VoiceToken {
            let issued = Date(timeIntervalSince1970: 0)
            return VoiceToken(token: "t", credential: "c", identity: "i", number: nil, prefix: "p", issuedAt: issued, expiresAt: issued.addingTimeInterval(lifetime))
        }
        // An hour: 80% of it, well clear of the 30 s margin.
        XCTAssertEqual(TokenExchange.refreshDelay(for: token(lifetime: 3600)), 2880)
        // Two minutes: the margin wins, at least half the lifetime.
        XCTAssertEqual(TokenExchange.refreshDelay(for: token(lifetime: 120)), 90)
        // Forty seconds: never before half its lifetime.
        XCTAssertEqual(TokenExchange.refreshDelay(for: token(lifetime: 40)), 20)
    }

    func testRetryDelayDoublesToTheMaximumWithJitter() {
        XCTAssertEqual(TokenExchange.retryDelay(retry: 0, random: { 0 }), 0.5)
        XCTAssertEqual(TokenExchange.retryDelay(retry: 3, random: { 0 }), 4)
        XCTAssertEqual(TokenExchange.retryDelay(retry: 10, random: { 0 }), 8)
        XCTAssertEqual(TokenExchange.retryDelay(retry: 10, random: { 1 }), 6, accuracy: 0.0001)
        XCTAssertEqual(TokenExchange.offlineRetryDelay(random: { 0 }), 30)
    }

    func testDatesWithAndWithoutFractionsParse() {
        XCTAssertNotNil(TokenExchange.parseDate("2026-10-31T10:00:00Z"))
        XCTAssertNotNil(TokenExchange.parseDate("2026-10-31T10:00:00.123Z"))
        XCTAssertNil(TokenExchange.parseDate("yesterday"))
    }
}
