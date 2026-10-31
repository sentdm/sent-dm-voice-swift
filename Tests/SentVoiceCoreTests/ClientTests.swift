import Foundation
import XCTest
@testable import SentVoiceCore

final class ClientTests: XCTestCase {
    func testRegisterExchangesTheTokenAndRegistersTheCredential() async throws {
        let (client, adapter, http) = SentVoiceClient.testClient()
        let events = Recorder<ClientEvent>()
        client.on { events.append($0) }
        XCTAssertEqual(client.state, .unregistered)

        try await client.register()

        XCTAssertEqual(client.state, .registered)
        XCTAssertEqual(client.identity, "alice")
        XCTAssertEqual(client.number, "+15555550100")
        XCTAssertEqual(adapter.registered, ["eyJ.credential"])
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(events.events, [.registering, .registered])

        try await client.register()
        XCTAssertEqual(http.requests.count, 1, "already registered: no second exchange")
        await client.destroy()
    }

    func testRegisterFailsWithTheTokenErrorAndStaysUnregistered() async {
        let (client, _, _) = SentVoiceClient.testClient(http: FakeHTTP([FakeHTTP.ok("{}", status: 401)]))
        let events = Recorder<ClientEvent>()
        client.on { events.append($0) }
        await XCTAssertThrowsCode(.tokenInvalid) { try await client.register() }
        XCTAssertEqual(client.state, .unregistered)
        XCTAssertEqual(events.events.count, 2)
        if case .error(let error)? = events.events.last { XCTAssertEqual(error.code, .tokenInvalid) } else { XCTFail("expected an error event") }
        await client.destroy()
    }

    func testRegisterRetriesARetriableFailure() async throws {
        let http = FakeHTTP([.failure(Unreachable()), FakeHTTP.ok(exchangeBody)])
        let (client, _, _) = SentVoiceClient.testClient(http: http, registerRetries: 1)
        try await client.register()
        XCTAssertEqual(client.state, .registered)
        XCTAssertEqual(http.requests.count, 2)
        await client.destroy()
    }

    func testConnectNeedsARegisteredClient() async {
        let (client, _, _) = SentVoiceClient.testClient()
        await XCTAssertThrowsCode(.notRegistered) { _ = try await client.connect(to: "+14155551234") }
    }

    func testConnectValidatesTheAddress() async throws {
        let (client, adapter, _) = SentVoiceClient.testClient()
        try await client.register()
        await XCTAssertThrowsCode(.invalidAddress) { _ = try await client.connect(to: "415 555 1234") }
        await XCTAssertThrowsCode(.invalidAddress) { _ = try await client.connect(to: "bob with spaces") }
        await XCTAssertThrowsCode(.invalidAddress) { _ = try await client.joinConference(name: "no/slashes") }
        XCTAssertTrue(adapter.calls.isEmpty)
        await client.destroy()
    }

    func testConnectPlacesANumberCallAndFollowsTheProvider() async throws {
        let (client, adapter, _) = SentVoiceClient.testClient()
        try await client.register()
        let clientEvents = Recorder<ClientEvent>()
        client.on { clientEvents.append($0) }

        let call = try await client.connect(to: "+14155551234")
        XCTAssertEqual(adapter.calls, [.number("+14155551234")])
        XCTAssertEqual(call.id, "call_1")
        XCTAssertEqual(call.state, .initiated)
        XCTAssertEqual(call.direction, .outbound)
        XCTAssertEqual(call.to, .number("+14155551234"))
        XCTAssertEqual(call.from, .user(identity: "alice"))
        XCTAssertEqual(client.activeCall?.id, "call_1")
        XCTAssertEqual(clientEvents.events, [.activeCallChanged(call)])

        let callEvents = Recorder<CallEvent>()
        call.on { callEvents.append($0) }
        adapter.report("call_1", .ringing)
        adapter.report("call_1", .answered)
        adapter.report("call_1", .connected)
        XCTAssertEqual(call.state, .connected)
        XCTAssertNotNil(call.connectedTime)

        try call.mute(true)
        XCTAssertTrue(call.isMuted)
        try call.sendDigits("1#")
        XCTAssertEqual(adapter.digits.map(\.1), ["1#"])
        try await XCTAssertThrowsCodeSync(.invalidAddress) { try call.sendDigits("hello") }

        try await call.hangup()
        XCTAssertEqual(adapter.hangups, ["call_1"])
        XCTAssertEqual(call.state, .completed)
        XCTAssertNil(client.activeCall)
        XCTAssertEqual(callEvents.events, [.ringing, .answered, .connected, .muteChanged(true), .disconnected(state: .completed, error: nil)])
        XCTAssertEqual(clientEvents.events.last, .activeCallChanged(nil))
        await client.destroy()
    }

    func testUserAndConferenceTargetsCarryTheTokenPrefix() async throws {
        let (client, adapter, _) = SentVoiceClient.testClient()
        try await client.register()
        let first = try await client.connect(to: "bob-1")
        XCTAssertEqual(adapter.calls.last, .user(id: "acme_bob-1"))
        XCTAssertEqual(first.to, .user(identity: "bob-1"))
        adapter.report(first.id, .disconnected(state: .failed, error: SentVoiceError(code: .callFailed)))
        XCTAssertEqual(first.state, .failed)
        XCTAssertEqual(first.error?.code, .callFailed)

        let room = try await client.joinConference(name: "standup")
        XCTAssertEqual(adapter.calls.last, .conference(room: "acme_standup"))
        XCTAssertEqual(room.to, .conference(name: "standup"))
        await client.destroy()
    }

    func testOneCallAtATime() async throws {
        let (client, _, _) = SentVoiceClient.testClient()
        try await client.register()
        _ = try await client.connect(to: "+14155551234")
        await XCTAssertThrowsCode(.callInProgress) { _ = try await client.connect(to: "+14155550000") }
        await client.destroy()
    }

    func testAnEventTheContractRefusesIsIgnored() async throws {
        let (client, adapter, _) = SentVoiceClient.testClient()
        try await client.register()
        let call = try await client.connect(to: "+14155551234")
        let events = Recorder<CallEvent>()
        call.on { events.append($0) }
        adapter.report("call_1", .connected)
        adapter.report("call_1", .ringing)
        adapter.report("somebody-else", .disconnected(state: .completed, error: nil))
        XCTAssertEqual(call.state, .connected)
        XCTAssertEqual(events.events, [.connected])
        XCTAssertEqual(client.activeCall?.id, "call_1")
        await client.destroy()
    }

    func testUnregisterHangsUpAndTellsTheProvider() async throws {
        let (client, adapter, _) = SentVoiceClient.testClient()
        let events = Recorder<ClientEvent>()
        client.on { events.append($0) }
        try await client.register()
        _ = try await client.connect(to: "+14155551234")
        try await client.unregister()
        XCTAssertEqual(adapter.hangups, ["call_1"])
        XCTAssertEqual(adapter.unregisterCalls, 1)
        XCTAssertEqual(client.state, .unregistered)
        XCTAssertNil(client.identity)
        XCTAssertEqual(events.events.last, .unregistered)
        await client.destroy()
        XCTAssertEqual(client.state, .destroyed)
        await XCTAssertThrowsCode(.notRegistered) { try await client.register() }
    }

    func testQualityAverages() {
        let payload = SentVoiceClient.average([CallStats(rttMs: 10, jitterMs: nil, packetLoss: 0.2), CallStats(rttMs: 30, jitterMs: 4, packetLoss: nil)])
        XCTAssertEqual(payload["samples"], .int(2))
        XCTAssertEqual(payload["rtt_ms"], .double(20))
        XCTAssertEqual(payload["jitter_ms"], .double(4))
        XCTAssertEqual(payload["packet_loss"], .double(0.2))
    }

    func testValidation() {
        XCTAssertTrue(Validation.isE164("+14155551234"))
        XCTAssertFalse(Validation.isE164("+0123"))
        XCTAssertFalse(Validation.isE164("14155551234"))
        XCTAssertTrue(Validation.isName("alice_01-x"))
        XCTAssertFalse(Validation.isName(""))
        XCTAssertFalse(Validation.isName(String(repeating: "a", count: 201)))
    }
}

func XCTAssertThrowsCodeSync(_ code: ErrorCode, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) async throws {
    do {
        try body()
        XCTFail("expected \(code.rawValue)", file: file, line: line)
    } catch let error as SentVoiceError {
        XCTAssertEqual(error.code, code, file: file, line: line)
    }
}
