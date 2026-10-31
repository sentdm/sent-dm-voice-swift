import Foundation

/// Where a call goes.
public enum CallTarget: Sendable, Equatable {
    /// A phone number in E.164 format.
    case number(String)
    /// A user of your app, as the provider knows them (the identity, qualified by the token's prefix).
    case user(id: String)
    /// A conference room, as the provider knows it.
    case conference(room: String)
}

/// Who is on the other end of a call, as the app sees it.
public enum Address: Sendable, Equatable {
    case number(String)
    case user(identity: String)
    case conference(name: String)
}

/// A snapshot of a call's media quality.
public struct CallStats: Sendable, Equatable {
    public var rttMs: Double?
    public var jitterMs: Double?
    public var packetLoss: Double?

    public init(rttMs: Double? = nil, jitterMs: Double? = nil, packetLoss: Double? = nil) {
        self.rttMs = rttMs
        self.jitterMs = jitterMs
        self.packetLoss = packetLoss
    }
}

/// A warning the provider raised about a call's media, or cleared.
public struct QualityWarning: Sendable, Equatable {
    public let metric: String
    public let cleared: Bool

    public init(metric: String, cleared: Bool) {
        self.metric = metric
        self.cleared = cleared
    }
}

/// What the provider reports about a call, in the contract's words.
public enum AdapterCallEvent: Sendable, Equatable {
    case ringing
    case answered
    case connected
    case reconnecting
    case reconnected
    /// The call ended in `state` (completed, failed, busy or noAnswer), with the error that ended it when there is one.
    case disconnected(state: CallState, error: SentVoiceError?)
    case muteChanged(Bool)
    case qualityWarning(QualityWarning)
    case error(SentVoiceError)
}

/// The provider's SDK behind the client. The core drives it and never sees the provider's types.
public protocol ProviderAdapter: AnyObject, Sendable {
    /// Registers with the credential Sent issued, or re-registers with a fresh one. `number` is the Sent
    /// number the user is bound to, which the provider shows as the caller id on calls to phones.
    func register(credential: String, number: String?) async throws
    func unregister() async throws
    /// Places a call and returns the provider's id for it.
    func call(_ target: CallTarget) async throws -> String
    func hangup(callId: String) async throws
    func mute(callId: String, muted: Bool) throws
    func sendDigits(callId: String, digits: String) throws
    func stats(callId: String) async throws -> CallStats
    /// The core sets this once; the adapter calls it for every event of every call, on any thread.
    func setCallEventHandler(_ handler: @escaping @Sendable (String, AdapterCallEvent) -> Void)
}
