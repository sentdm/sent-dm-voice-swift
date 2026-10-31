import Foundation
import XCTest
@testable import SentVoiceCore

/// An HTTP client that answers from a script and records what it was asked.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    struct Answer { let status: Int; let body: Data }
    private let lock = NSLock()
    private var answers: [Result<Answer, Error>]
    private(set) var requests: [URLRequest] = []

    init(_ answers: [Result<Answer, Error>]) { self.answers = answers }

    static func ok(_ json: String, status: Int = 200) -> Result<Answer, Error> {
        .success(Answer(status: status, body: Data(json.utf8)))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        requests.append(request)
        let next = answers.isEmpty ? FakeHTTP.ok("{}", status: 200) : answers.removeFirst()
        lock.unlock()
        let answer = try next.get()
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil)!
        return (answer.body, response)
    }
}

struct Unreachable: Error {}

let exchangeBody = """
{"data":{"credential":"eyJ.credential","identity":"alice","number":"+15555550100","prefix":"acme_",
"issued_at":"2026-10-31T10:00:00.000Z","expires_at":"2026-10-31T11:00:00.000Z"}}
"""

func XCTAssertThrowsCode(_ code: ErrorCode, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Void) async {
    do {
        try await body()
        XCTFail("expected \(code.rawValue)", file: file, line: line)
    } catch let error as SentVoiceError {
        XCTAssertEqual(error.code, code, file: file, line: line)
    } catch {
        XCTFail("expected a SentVoiceError, got \(error)", file: file, line: line)
    }
}
