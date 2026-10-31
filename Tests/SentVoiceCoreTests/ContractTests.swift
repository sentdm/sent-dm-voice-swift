import Foundation
import XCTest
@testable import SentVoiceCore

final class ContractTests: XCTestCase {
    func testEveryStateHasATransitionList() {
        for state in CallState.allCases {
            XCTAssertNotNil(Contract.callTransitions[state], "\(state) is missing from the transitions")
        }
    }

    func testTerminalStatesStayPut() {
        for state in [CallState.completed, .failed, .busy, .noAnswer] {
            XCTAssertTrue(state.isTerminal)
            for next in CallState.allCases {
                XCTAssertFalse(state.canTransition(to: next))
            }
        }
    }

    func testOutboundStartsInitiatedAndInboundRinging() {
        XCTAssertEqual(CallState.initial(for: .outbound), .initiated)
        XCTAssertEqual(CallState.initial(for: .inbound), .ringing)
    }

    func testStateMachineRefusesWhatTheContractDoesNotAllow() {
        var machine = CallStateMachine(direction: .outbound)
        XCTAssertTrue(machine.transition(to: .ringing))
        XCTAssertFalse(machine.transition(to: .initiated), "a call never goes back to initiated")
        XCTAssertTrue(machine.transition(to: .connected))
        XCTAssertTrue(machine.transition(to: .reconnecting))
        XCTAssertTrue(machine.transition(to: .connected))
        XCTAssertTrue(machine.transition(to: .completed))
        XCTAssertFalse(machine.transition(to: .connected))
        XCTAssertEqual(machine.state, .completed)
    }

    func testEveryErrorClassMatchesItsCode() {
        XCTAssertEqual(Contract.errorClasses.count, 8)
        for spec in Contract.errorClasses {
            let error = SentVoiceError(code: spec.code)
            XCTAssertEqual(error.category, spec.category, spec.name)
            XCTAssertEqual(error.retriable, spec.retriable, spec.name)
            XCTAssertFalse(error.message.isEmpty, spec.name)
        }
    }

    func testCodesWithoutAClassStillHaveACategoryAndMessage() {
        let classCodes = Set(Contract.errorClasses.map(\.code))
        for code in ErrorCode.allCases where !classCodes.contains(code) {
            let error = SentVoiceError(code: code)
            XCTAssertFalse(error.retriable, code.rawValue)
            XCTAssertFalse(error.message.hasPrefix("Voice error"), "\(code.rawValue) has no written message")
        }
        XCTAssertEqual(SentVoiceError(code: .invalidAddress).category, .validation)
        XCTAssertEqual(SentVoiceError(code: .callInProgress).category, .validation)
    }

    func testTokenTimingMatchesTheContractFile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("contract/voice-client.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let token = try XCTUnwrap(json["token"] as? [String: Any])
        XCTAssertEqual(TokenTiming.refreshShare, token["refreshShare"] as? Double)
        XCTAssertEqual(TokenTiming.refreshMargin, (token["refreshMarginMs"] as? Double).map { $0 / 1000 })
        XCTAssertEqual(TokenTiming.maxRetryDelay, (token["maxRetryDelayMs"] as? Double).map { $0 / 1000 })
        XCTAssertEqual(Contract.version, json["version"] as? String)
    }
}
