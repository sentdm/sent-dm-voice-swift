import Foundation
import XCTest
@testable import SentVoiceCore

final class TelemetryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_793_440_800) // 2026-10-30T22:00:00Z

    func testFlushPostsABatchWithTheVoiceTokenAndTheSDKVersion() async throws {
        let http = FakeHTTP([FakeHTTP.ok("{}", status: 202)])
        let telemetry = Telemetry(baseURL: URL(string: "https://api.example.test")!, sdkVersion: "1.2.3", http: http)
        telemetry.record(.registerCompleted, payload: ["attempt": .int(1)], at: date)
        telemetry.record(.callStarted, callId: "call_1", payload: ["direction": .string("outbound")], at: date)
        telemetry.useToken("voice.token")
        await telemetry.flush()

        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/v3/voice/telemetry")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer voice.token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["sdk_version"] as? String, "1.2.3")
        let events = try XCTUnwrap(body["events"] as? [[String: Any]])
        XCTAssertEqual(events.map { $0["type"] as? String }, ["register.completed", "call.started"])
        XCTAssertEqual(events[1]["call_id"] as? String, "call_1")
        XCTAssertEqual(events[0]["occurred_at"] as? String, "2026-10-30T22:00:00.000Z")
        XCTAssertEqual((events[1]["payload"] as? [String: Any])?["direction"] as? String, "outbound")
        XCTAssertTrue(telemetry.pending.isEmpty)
        telemetry.destroy()
    }

    func testNothingIsSentWithoutAToken() async {
        let http = FakeHTTP([])
        let telemetry = Telemetry(http: http)
        telemetry.record(.clientInfo, at: date)
        await telemetry.flush()
        XCTAssertTrue(http.requests.isEmpty)
        XCTAssertEqual(telemetry.pending.count, 1)
        telemetry.destroy()
    }

    func testAFailedBatchIsRetriedOnceThenDropped() async {
        let http = FakeHTTP([FakeHTTP.ok("", status: 500), .failure(Unreachable()), FakeHTTP.ok("", status: 500)])
        let telemetry = Telemetry(http: http)
        telemetry.useToken("t")
        telemetry.record(.clientError, at: date)
        await telemetry.flush()
        XCTAssertEqual(telemetry.pending.count, 1, "kept for one retry")
        await telemetry.flush()
        XCTAssertTrue(telemetry.pending.isEmpty, "dropped after the retry failed")
        XCTAssertEqual(http.requests.count, 2)
        telemetry.destroy()
    }

    func testLongTextIsClippedAndTheQueueIsBounded() throws {
        let telemetry = Telemetry(http: FakeHTTP([]))
        telemetry.record(.clientError, payload: ["message": .string(String(repeating: "x", count: 900))], at: date)
        let payload = try XCTUnwrap(telemetry.pending[0].json["payload"] as? [String: Any])
        XCTAssertEqual((payload["message"] as? String)?.count, Telemetry.maxTextLength)
        for _ in 0..<150 { telemetry.record(.clientInfo, at: date) }
        XCTAssertEqual(telemetry.pending.count, Telemetry.maxEvents)
        telemetry.destroy()
    }

    func testBigBacklogsSplitIntoBatchesUnderTheBodyLimit() {
        let big = TelemetryEvent(type: .clientError, occurredAt: date, payload: ["provider_error": .string(String(repeating: "e", count: 500))])
        let entries = (0..<200).map { _ in Telemetry.Entry(event: big, retried: false) }
        let batches = Telemetry.split(entries, sdkVersion: "0")
        XCTAssertGreaterThan(batches.count, 1)
        for batch in batches {
            XCTAssertLessThanOrEqual(Telemetry.body(batch, sdkVersion: "0").count, Telemetry.maxBodyBytes + 200)
        }
        XCTAssertEqual(batches.flatMap { $0 }.count, 200)
    }

    func testDisabledTelemetryRecordsNothing() async {
        let http = FakeHTTP([])
        let telemetry = Telemetry(http: http, disabled: true)
        telemetry.useToken("t")
        telemetry.record(.clientInfo, at: date)
        await telemetry.flush()
        XCTAssertTrue(http.requests.isEmpty)
    }
}
