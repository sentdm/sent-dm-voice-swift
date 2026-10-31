import Foundation

/// An error the Voice Client reports: a contract code, its category, whether retrying can help,
/// a message written for the app's logs, and the provider's own detail when there is one.
public struct SentVoiceError: Error, Sendable, Equatable, CustomStringConvertible {
    public let code: ErrorCode
    public let category: ErrorCategory
    public let retriable: Bool
    public let message: String
    public let providerDetail: String?

    public init(code: ErrorCode, message: String? = nil, providerDetail: String? = nil) {
        let spec = Contract.errorClasses.first { $0.code == code }
        self.code = code
        self.category = spec?.category ?? SentVoiceError.fallbackCategory[code] ?? .signaling
        self.retriable = spec?.retriable ?? false
        self.message = message ?? SentVoiceError.defaultMessage[code] ?? "Voice error \(code.rawValue)."
        self.providerDetail = providerDetail
    }

    public var description: String { "\(code.rawValue): \(message)" }

    /// Codes the contract names without an error class.
    static let fallbackCategory: [ErrorCode: ErrorCategory] = [
        .invalidAddress: .validation,
        .callInProgress: .validation,
        .unknown: .signaling,
    ]

    static let defaultMessage: [ErrorCode: String] = [
        .tokenExpired: "The voice token expired and could not be refreshed.",
        .tokenInvalid: "The token provider returned an invalid voice token.",
        .notRegistered: "The client is not registered.",
        .mediaPermissionDenied: "Microphone permission was denied.",
        .callRejected: "The call was rejected.",
        .callFailed: "The call failed.",
        .network: "The network connection failed.",
        .capabilityUnsupported: "This capability is not supported.",
        .invalidAddress: "The address is invalid.",
        .callInProgress: "A call is in progress or an incoming call is waiting; end or decline it first.",
        .unknown: "An unexpected error occurred.",
    ]
}
