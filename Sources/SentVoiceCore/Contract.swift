// Generated from contract/voice-client.json 1.0.0 by scripts/generate-contract.py. Do not edit.

import Foundation

/// The Voice Client contract this SDK implements: the vocabulary every Sent Voice Client SDK shares.
public enum Contract {
    public static let version = "1.0.0"

    /// Which call states a call may move to from each state.
    public static let callTransitions: [CallState: [CallState]] = [
        .initiated: [.ringing, .answered, .connected, .completed, .failed, .busy, .noAnswer],
        .ringing: [.answered, .connected, .completed, .failed, .busy, .noAnswer],
        .answered: [.connected, .completed, .failed, .busy, .noAnswer],
        .connected: [.reconnecting, .completed, .failed, .busy, .noAnswer],
        .reconnecting: [.connected, .completed, .failed, .busy, .noAnswer],
        .completed: [],
        .failed: [],
        .busy: [],
        .noAnswer: [],
    ]

    /// The error classes the contract names, with the category and retriability of each.
    public static let errorClasses: [ErrorClass] = [
        ErrorClass(name: "TokenExpiredError", code: .tokenExpired, category: .auth, retriable: true),
        ErrorClass(name: "TokenInvalidError", code: .tokenInvalid, category: .auth, retriable: false),
        ErrorClass(name: "NotRegisteredError", code: .notRegistered, category: .validation, retriable: false),
        ErrorClass(name: "MediaPermissionError", code: .mediaPermissionDenied, category: .media, retriable: false),
        ErrorClass(name: "CallRejectedError", code: .callRejected, category: .signaling, retriable: false),
        ErrorClass(name: "CallFailedError", code: .callFailed, category: .signaling, retriable: false),
        ErrorClass(name: "NetworkError", code: .network, category: .network, retriable: true),
        ErrorClass(name: "CapabilityUnsupportedError", code: .capabilityUnsupported, category: .capability, retriable: false),
    ]

    /// The fields a telemetry payload may carry.
    public static let telemetryPayloadFields: [String] = ["browser", "browser_version", "os", "os_version", "device_type", "duration_ms", "attempt", "direction", "outcome", "rtt_ms", "jitter_ms", "packet_loss", "samples", "code", "category", "message", "retriable", "provider_error"]
}

/// The states a client moves through.
public enum ClientState: String, CaseIterable, Sendable, Codable {
    case unregistered
    case registering
    case registered
    case offline
    case destroyed
}

/// The events a client emits.
public enum ClientEventName: String, CaseIterable, Sendable, Codable {
    case registering
    case registered
    case unregistered
    case incomingCall
    case activeCallChanged
    case offline
    case tokenWillExpire
    case error
}

/// The states a call moves through.
public enum CallState: String, CaseIterable, Sendable, Codable {
    case initiated
    case ringing
    case answered
    case connected
    case reconnecting
    case completed
    case failed
    case busy
    case noAnswer
}

extension CallState {
    /// The state a call starts in, by direction.
    public static func initial(for direction: CallDirection) -> CallState {
        switch direction {
        case .inbound: return .ringing
        case .outbound: return .initiated
        }
    }

    /// Whether the contract allows a call in this state to move to `next`.
    public func canTransition(to next: CallState) -> Bool {
        Contract.callTransitions[self]?.contains(next) ?? false
    }

    /// A state no call leaves.
    public var isTerminal: Bool { Contract.callTransitions[self]?.isEmpty ?? true }
}

/// Who placed the call.
public enum CallDirection: String, CaseIterable, Sendable, Codable {
    case inbound
    case outbound
}

/// The events a call emits.
public enum CallEventName: String, CaseIterable, Sendable, Codable {
    case ringing
    case answered
    case connected
    case reconnecting
    case reconnected
    case disconnected
    case muteChanged
    case qualityWarning
    case error
}

/// The events an incoming-call invite emits.
public enum InviteEventName: String, CaseIterable, Sendable, Codable {
    case accepted
    case rejected
    case cancelled
}

/// The events the audio layer emits.
public enum AudioEventName: String, CaseIterable, Sendable, Codable {
    case deviceChanged
}

/// The error codes an SDK error carries.
public enum ErrorCode: String, CaseIterable, Sendable, Codable {
    case tokenExpired = "TOKEN_EXPIRED"
    case tokenInvalid = "TOKEN_INVALID"
    case notRegistered = "NOT_REGISTERED"
    case mediaPermissionDenied = "MEDIA_PERMISSION_DENIED"
    case callRejected = "CALL_REJECTED"
    case callFailed = "CALL_FAILED"
    case network = "NETWORK"
    case capabilityUnsupported = "CAPABILITY_UNSUPPORTED"
    case invalidAddress = "INVALID_ADDRESS"
    case callInProgress = "CALL_IN_PROGRESS"
    case unknown = "UNKNOWN"
}

/// The categories an SDK error belongs to.
public enum ErrorCategory: String, CaseIterable, Sendable, Codable {
    case auth
    case media
    case signaling
    case network
    case validation
    case capability
}

/// An error class the contract names.
public struct ErrorClass: Sendable, Equatable {
    public let name: String
    public let code: ErrorCode
    public let category: ErrorCategory
    public let retriable: Bool
}

/// When a voice token is refreshed and how failed fetches are retried, in seconds.
public enum TokenTiming {
    public static let refreshShare: Double = 0.8
    public static let refreshMargin: TimeInterval = 30.0
    public static let initialRetryDelay: TimeInterval = 0.5
    public static let maxRetryDelay: TimeInterval = 8.0
    public static let offlineRetryInterval: TimeInterval = 30.0
}

/// The events the SDK reports to Sent.
public enum TelemetryEventName: String, CaseIterable, Sendable, Codable {
    case registerCompleted = "register.completed"
    case registerFailed = "register.failed"
    case unregisterCompleted = "unregister.completed"
    case clientInfo = "client.info"
    case clientError = "client.error"
    case callStarted = "call.started"
    case callConnected = "call.connected"
    case callQuality = "call.quality"
    case callEnded = "call.ended"
}
