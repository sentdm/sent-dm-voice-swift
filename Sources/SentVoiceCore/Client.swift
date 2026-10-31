import Foundation

/// How the client is set up.
public struct SentVoiceOptions: Sendable {
    /// Returns a voice token from your backend, which mints it with `POST /v3/voice/tokens`.
    public var tokenProvider: @Sendable () async throws -> String
    /// The Sent API origin the token is exchanged with and telemetry goes to.
    public var baseURL: URL
    /// How many times registering or refreshing the voice token is retried before the client gives up.
    public var registerRetries: Int
    public var telemetryDisabled: Bool
    /// Where the client's own log lines go, if anywhere.
    public var log: (@Sendable (LogLevel, String) -> Void)?

    public init(
        tokenProvider: @escaping @Sendable () async throws -> String,
        baseURL: URL = SentAPI.defaultBaseURL,
        registerRetries: Int = 3,
        telemetryDisabled: Bool = false,
        log: (@Sendable (LogLevel, String) -> Void)? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
        self.registerRetries = registerRetries
        self.telemetryDisabled = telemetryDisabled
        self.log = log
    }
}

public enum LogLevel: String, Sendable {
    case error, warn, info, debug
}

/// What the client reports as it goes.
public enum ClientEvent: Sendable, Equatable {
    case registering
    case registered
    case unregistered
    /// The call in progress changed: a placed call, or nil once it ended.
    case activeCallChanged(Call?)
    /// The client lost its registration and could not get it back; register again when the cause is fixed.
    case offline(SentVoiceError)
    /// The voice token is about to expire and the next refresh is due.
    case tokenWillExpire(expiresAt: Date)
    case error(SentVoiceError)

    public static func == (lhs: ClientEvent, rhs: ClientEvent) -> Bool {
        switch (lhs, rhs) {
        case (.registering, .registering), (.registered, .registered), (.unregistered, .unregistered): return true
        case (.activeCallChanged(let a), .activeCallChanged(let b)): return a?.id == b?.id
        case (.offline(let a), .offline(let b)), (.error(let a), .error(let b)): return a == b
        case (.tokenWillExpire(let a), .tokenWillExpire(let b)): return a == b
        default: return false
        }
    }
}

/// The Sent Voice Client: registers the user with a voice token and places calls.
///
/// One call at a time. Events reach listeners in order, on whatever thread reported them; hop to the main
/// thread before touching UI.
public final class SentVoiceClient: @unchecked Sendable {
    private let options: SentVoiceOptions
    private let adapter: ProviderAdapter
    private let http: HTTPClient
    private let telemetry: Telemetry
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var clientState: ClientState = .unregistered
    private var token: VoiceToken?
    private var active: Call?
    private var listeners: [UUID: @Sendable (ClientEvent) -> Void] = [:]
    private var refreshTask: Task<Void, Never>?
    private var qualityTask: Task<Void, Never>?
    private var registerTask: Task<Void, Error>?

    public init(options: SentVoiceOptions, adapter: ProviderAdapter, http: HTTPClient = URLSession.shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.options = options
        self.adapter = adapter
        self.http = http
        self.now = now
        self.telemetry = Telemetry(baseURL: options.baseURL, http: http, disabled: options.telemetryDisabled)
        adapter.setCallEventHandler { [weak self] callId, event in self?.handle(callId: callId, event: event) }
    }

    public var state: ClientState { lock.locked { clientState } }
    /// The user the voice token names, once registered.
    public var identity: String? { lock.locked { token?.identity } }
    /// The Sent number the user is bound to, once registered and when the token carries one.
    public var number: String? { lock.locked { token?.number } }
    /// The call in progress, if any.
    public var activeCall: Call? { lock.locked { active } }

    /// Listens to the client's events until the token is cancelled.
    @discardableResult
    public func on(_ listener: @escaping @Sendable (ClientEvent) -> Void) -> ListenerToken {
        let id = UUID()
        lock.locked { listeners[id] = listener }
        return ListenerToken { [weak self] in self?.lock.locked { _ = self?.listeners.removeValue(forKey: id) } }
    }

    /// Fetches a voice token, registers with it and keeps it refreshed. Safe to call again: a second call
    /// while registering waits for the first; once registered it returns at once.
    public func register() async throws {
        let (state, running) = lock.locked { (clientState, registerTask) }
        if state == .destroyed { throw SentVoiceError(code: .notRegistered, message: "The client was destroyed.") }
        if state == .registered { return }
        if let running {
            try await running.value
            return
        }
        let task = Task { try await self.doRegister() }
        lock.locked { registerTask = task }
        defer { lock.locked { registerTask = nil } }
        try await task.value
    }

    private func doRegister() async throws {
        setState(.registering, emit: .registering)
        var attempt = 0
        while true {
            attempt += 1
            do {
                let token = try await TokenExchange.fetch(tokenProvider: options.tokenProvider, baseURL: options.baseURL, http: http)
                try await adapter.register(credential: token.credential)
                lock.locked { self.token = token }
                telemetry.useToken(token.token)
                telemetry.record(.registerCompleted, payload: ["attempt": .int(attempt)], at: now())
                telemetry.record(.clientInfo, payload: Platform.info, at: now())
                setState(.registered, emit: .registered)
                scheduleRefresh(for: token)
                return
            } catch let error as SentVoiceError {
                telemetry.record(.registerFailed, payload: error.telemetryPayload.merging(["attempt": .int(attempt)]) { $1 }, at: now())
                guard error.retriable, attempt <= options.registerRetries else {
                    setState(.unregistered, emit: .error(error))
                    throw error
                }
                log(.warn, "Registering failed (attempt \(attempt)): \(error.message)")
                try await Task.sleep(nanoseconds: UInt64(TokenExchange.retryDelay(retry: attempt - 1) * 1_000_000_000))
            } catch {
                let wrapped = SentVoiceError(code: .unknown, message: "Registering failed: \(error)", providerDetail: "\(error)")
                setState(.unregistered, emit: .error(wrapped))
                throw wrapped
            }
        }
    }

    /// Ends the active call, unregisters from the provider and stops refreshing the token.
    public func unregister() async throws {
        let (state, call) = lock.locked { (clientState, active) }
        guard state == .registered || state == .offline else { return }
        if let call { try? await call.hangup() }
        lock.locked { refreshTask?.cancel(); refreshTask = nil }
        try await adapter.unregister()
        lock.locked { token = nil }
        telemetry.record(.unregisterCompleted, at: now())
        setState(.unregistered, emit: .unregistered)
    }

    /// Calls a phone number in E.164 format or another user of your app, by identity.
    public func connect(to: String) async throws -> Call {
        if Validation.isE164(to) {
            return try await place(to: .number(to)) { prefix in .number(to) }
        }
        guard Validation.isName(to) else {
            throw SentVoiceError(code: .invalidAddress, message: "'to' must be a phone number in E.164 format (for example +14155551234) or a user identity.")
        }
        return try await place(to: .user(identity: to)) { prefix in .user(id: prefix + to) }
    }

    /// Joins a conference by name; everyone who joins the same name is in the same room.
    public func joinConference(name: String) async throws -> Call {
        guard Validation.isName(name) else {
            throw SentVoiceError(code: .invalidAddress, message: "A conference name is letters, digits, - and _, up to 200 characters.")
        }
        return try await place(to: .conference(name: name)) { prefix in .conference(room: prefix + name) }
    }

    /// Unregisters and releases the client; it cannot be used afterwards.
    public func destroy() async {
        try? await unregister()
        lock.locked {
            refreshTask?.cancel(); refreshTask = nil
            qualityTask?.cancel(); qualityTask = nil
        }
        telemetry.destroy()
        setState(.destroyed, emit: nil)
        lock.locked { listeners.removeAll() }
    }

    private func place(to address: Address, target: (String) -> CallTarget) async throws -> Call {
        let (state, token, active) = lock.locked { (clientState, self.token, self.active) }
        guard state == .registered, let token else { throw SentVoiceError(code: .notRegistered) }
        guard active == nil else { throw SentVoiceError(code: .callInProgress) }
        let callId = try await adapter.call(target(token.prefix))
        let call = Call(
            id: callId, direction: .outbound, from: .user(identity: token.identity), to: address, startedAt: now(),
            actions: Call.Actions(
                hangup: { [adapter] in try await adapter.hangup(callId: callId) },
                mute: { [adapter] muted in try adapter.mute(callId: callId, muted: muted) },
                sendDigits: { [adapter] digits in try adapter.sendDigits(callId: callId, digits: digits) },
                stats: { [adapter] in try await adapter.stats(callId: callId) }
            )
        )
        lock.locked { self.active = call }
        telemetry.record(.callStarted, callId: callId, payload: ["direction": .string("outbound")], at: now())
        emit(.activeCallChanged(call))
        return call
    }

    private func handle(callId: String, event: AdapterCallEvent) {
        guard let call = lock.locked({ active }), call.id == callId else { return }
        guard let emitted = call.apply(event, at: now()) else { return }
        switch emitted {
        case .connected:
            telemetry.record(.callConnected, callId: callId, payload: ["duration_ms": .int(Int(now().timeIntervalSince(call.startedAt) * 1000))], at: now())
            startQualitySampling(for: call)
        case .disconnected(let state, let error):
            lock.locked { if active?.id == callId { active = nil }; qualityTask?.cancel(); qualityTask = nil }
            var payload: [String: TelemetryValue] = ["outcome": .string(state.rawValue), "duration_ms": .int(Int(now().timeIntervalSince(call.startedAt) * 1000))]
            if let error { payload.merge(error.telemetryPayload) { $1 } }
            telemetry.record(.callEnded, callId: callId, payload: payload, at: now())
            emit(.activeCallChanged(nil))
        case .error(let error):
            telemetry.record(.clientError, callId: callId, payload: error.telemetryPayload, at: now())
        default:
            break
        }
    }

    private func startQualitySampling(for call: Call) {
        lock.locked {
            qualityTask?.cancel()
            qualityTask = Task { [weak self, weak call] in
                var samples: [CallStats] = []
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard let self, let call, !call.state.isTerminal else { return }
                    if let stats = try? await call.stats() { samples.append(stats) }
                    if samples.count >= 6 {
                        self.telemetry.record(.callQuality, callId: call.id, payload: Self.average(samples), at: self.now())
                        samples = []
                    }
                }
            }
        }
    }

    static func average(_ samples: [CallStats]) -> [String: TelemetryValue] {
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        var payload: [String: TelemetryValue] = ["samples": .int(samples.count)]
        if let rtt = mean(samples.compactMap(\.rttMs)) { payload["rtt_ms"] = .double(rtt) }
        if let jitter = mean(samples.compactMap(\.jitterMs)) { payload["jitter_ms"] = .double(jitter) }
        if let loss = mean(samples.compactMap(\.packetLoss)) { payload["packet_loss"] = .double(loss) }
        return payload
    }

    private func scheduleRefresh(for token: VoiceToken) {
        lock.locked {
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                let delay = TokenExchange.refreshDelay(for: token)
                try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.emit(.tokenWillExpire(expiresAt: token.expiresAt))
                await self.refresh()
            }
        }
    }

    private func refresh() async {
        var attempt = 0
        while !Task.isCancelled {
            attempt += 1
            do {
                let fresh = try await TokenExchange.fetch(tokenProvider: options.tokenProvider, baseURL: options.baseURL, http: http)
                try await adapter.register(credential: fresh.credential)
                lock.locked { token = fresh }
                telemetry.useToken(fresh.token)
                if lock.locked({ clientState }) == .offline { setState(.registered, emit: .registered) }
                scheduleRefresh(for: fresh)
                return
            } catch let error as SentVoiceError where error.retriable && attempt <= options.registerRetries {
                log(.warn, "Refreshing the voice token failed (attempt \(attempt)): \(error.message)")
                try? await Task.sleep(nanoseconds: UInt64(TokenExchange.retryDelay(retry: attempt - 1) * 1_000_000_000))
            } catch {
                let reason = (error as? SentVoiceError).map { SentVoiceError(code: .tokenExpired, message: $0.message, providerDetail: $0.providerDetail) }
                    ?? SentVoiceError(code: .tokenExpired)
                setState(.offline, emit: .offline(reason))
                return
            }
        }
    }

    private func setState(_ state: ClientState, emit event: ClientEvent?) {
        lock.locked { clientState = state }
        if let event { emit(event) }
    }

    private func emit(_ event: ClientEvent) {
        let current = lock.locked { Array(listeners.values) }
        for listener in current { listener(event) }
    }

    private func log(_ level: LogLevel, _ message: String) {
        options.log?(level, message)
    }
}

/// What the client checks before it calls the provider.
public enum Validation {
    static let e164 = try! NSRegularExpression(pattern: "^\\+[1-9][0-9]{1,14}$")
    static let name = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{1,200}$")

    public static func isE164(_ value: String) -> Bool { matches(e164, value) }
    public static func isName(_ value: String) -> Bool { matches(name, value) }

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}

/// What the client says about the platform it runs on.
enum Platform {
    static var info: [String: TelemetryValue] {
        var payload: [String: TelemetryValue] = ["device_type": .string("mobile")]
        #if os(iOS)
        payload["os"] = .string("iOS")
        #elseif os(macOS)
        payload["os"] = .string("macOS")
        payload["device_type"] = .string("desktop")
        #endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        payload["os_version"] = .string("\(version.majorVersion).\(version.minorVersion)")
        return payload
    }
}

extension SentVoiceError {
    /// The error as a telemetry payload.
    var telemetryPayload: [String: TelemetryValue] {
        var payload: [String: TelemetryValue] = [
            "code": .string(code.rawValue), "category": .string(category.rawValue), "message": .string(message), "retriable": .bool(retriable),
        ]
        if let providerDetail { payload["provider_error"] = .string(providerDetail) }
        return payload
    }
}
