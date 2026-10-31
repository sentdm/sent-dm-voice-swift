import Foundation
import SentVoiceCore
import SinchRTC

/// The provider's iOS SDK behind the client: one provider client per registration, one delegate for every call.
/// The provider's callbacks arrive on the main queue; they are forwarded as they come.
final class SinchAdapter: NSObject, ProviderAdapter, @unchecked Sendable {
    private static let environmentHost = "ocra-euc1.api.sinch.com"
    private static let applicationPrefix = "//rtc.sinch.com/applications/"

    private let lock = NSLock()
    private var client: SinchClient?
    private var credential = ""
    private var calls: [String: SinchCall] = [:]
    private var handler: (@Sendable (String, AdapterCallEvent) -> Void)?
    private var starting: CheckedContinuation<Void, Error>?

    // MARK: ProviderAdapter

    func register(credential: String, number: String?) async throws {
        let subject = try Self.subject(of: credential)
        lock.lock()
        self.credential = credential
        let existing = client
        lock.unlock()
        if existing != nil { return }

        let client: SinchClient
        do {
            if let number {
                client = try SinchRTC.client(withApplicationKey: subject.applicationKey, environmentHost: Self.environmentHost, userId: subject.userId, cli: number)
            } else {
                client = try SinchRTC.client(withApplicationKey: subject.applicationKey, environmentHost: Self.environmentHost, userId: subject.userId)
            }
        } catch {
            throw SentVoiceError(code: .callFailed, message: "The calling client could not be created.", providerDetail: "\(error)")
        }
        client.delegate = self
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.client = client
            starting = continuation
            lock.unlock()
            client.start()
        }
    }

    func unregister() async throws {
        let (client, calls) = lock.locked { () -> (SinchClient?, [SinchCall]) in
            defer { self.client = nil; self.calls = [:] }
            return (self.client, Array(self.calls.values))
        }
        calls.forEach { $0.hangup() }
        client?.terminateGracefully()
    }

    func call(_ target: CallTarget) async throws -> String {
        guard let client = lock.locked({ client }) else { throw SentVoiceError(code: .notRegistered) }
        let result: Result<SinchCall, Error>
        switch target {
        case .number(let number): result = client.callClient.callPhoneNumber(number)
        case .user(let id): result = client.callClient.callUser(withId: id)
        case .conference(let room): result = client.callClient.callConference(withId: room)
        }
        switch result {
        case .success(let call):
            call.delegate = self
            lock.locked { calls[call.callId] = call }
            return call.callId
        case .failure(let error):
            throw SentVoiceError(code: .callFailed, message: "The call could not be placed.", providerDetail: "\(error)")
        }
    }

    func hangup(callId: String) async throws {
        lock.locked { calls[callId] }?.hangup()
    }

    func mute(callId: String, muted: Bool) throws {
        guard let client = lock.locked({ client }) else { throw SentVoiceError(code: .notRegistered) }
        if muted { client.audioController.mute() } else { client.audioController.unmute() }
        emit(callId, .muteChanged(muted))
    }

    func sendDigits(callId: String, digits: String) throws {
        guard let call = lock.locked({ calls[callId] }) else { throw SentVoiceError(code: .callFailed, message: "The call is over.") }
        call.sendDTMF(digits)
    }

    func stats(callId: String) async throws -> CallStats {
        // The provider's iOS SDK reports quality as warning events rather than numbers.
        CallStats()
    }

    func setCallEventHandler(_ handler: @escaping @Sendable (String, AdapterCallEvent) -> Void) {
        lock.locked { self.handler = handler }
    }

    // MARK: Credential

    /// The application key and user id a credential names, read from its claims without verifying it.
    static func subject(of credential: String) throws -> (applicationKey: String, userId: String) {
        let parts = credential.split(separator: ".")
        guard parts.count >= 2 else { throw SentVoiceError(code: .tokenInvalid) }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard
            let data = Data(base64Encoded: payload),
            let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let iss = claims["iss"] as? String, iss.hasPrefix(applicationPrefix),
            let sub = claims["sub"] as? String, let usersRange = sub.range(of: "/users/")
        else { throw SentVoiceError(code: .tokenInvalid, message: "The credential names no application and user.") }
        return (String(iss.dropFirst(applicationPrefix.count)), String(sub[usersRange.upperBound...]))
    }

    private func emit(_ callId: String, _ event: AdapterCallEvent) {
        lock.locked { handler }?(callId, event)
    }

    /// What the provider's end cause means in the contract's words.
    static func ended(_ details: SinchCallDetails) -> AdapterCallEvent {
        switch details.endCause {
        case .denied:
            return .disconnected(state: .busy, error: nil)
        case .noAnswer, .timeout:
            return .disconnected(state: .noAnswer, error: nil)
        case .inactive:
            return .disconnected(state: .failed, error: SentVoiceError(code: .callFailed, message: "The call was ended after no media flowed.", providerDetail: "inactive"))
        case .error:
            let detail = details.error.map { "\($0)" }
            return .disconnected(state: .failed, error: SentVoiceError(code: .callFailed, providerDetail: detail))
        default:
            return .disconnected(state: .completed, error: nil)
        }
    }
}

extension SinchAdapter: SinchClientDelegate {
    func clientRequiresRegistrationCredentials(_ client: SinchClient, withCallback callback: SinchClientRegistration) {
        callback.register(withJWT: lock.locked { credential })
    }

    func clientDidStart(_ client: SinchClient) {
        lock.locked { starting }?.resume()
        lock.locked { starting = nil }
    }

    func clientDidFail(_ client: SinchClient, error: Error) {
        let waiting = lock.locked { () -> CheckedContinuation<Void, Error>? in
            defer { starting = nil; self.client = nil }
            return starting
        }
        waiting?.resume(throwing: SentVoiceError(code: .tokenInvalid, message: "The provider refused the registration.", providerDetail: "\(error)"))
    }
}

extension SinchAdapter: SinchCallDelegate {
    func callDidProgress(_ call: SinchCall) { emit(call.callId, .ringing) }
    func callDidRing(_ call: SinchCall) { emit(call.callId, .ringing) }
    func callDidAnswer(_ call: SinchCall) { emit(call.callId, .answered) }
    func callDidEstablish(_ call: SinchCall) { emit(call.callId, .connected) }

    func callDidEnd(_ call: SinchCall) {
        lock.locked { _ = calls.removeValue(forKey: call.callId) }
        emit(call.callId, Self.ended(call.details))
    }
}
