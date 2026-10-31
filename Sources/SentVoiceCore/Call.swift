import Foundation

/// What a call reports as it goes.
public enum CallEvent: Sendable, Equatable {
    case ringing
    case answered
    case connected
    case reconnecting
    case reconnected
    /// The call ended in `state`, with the error that ended it when there is one.
    case disconnected(state: CallState, error: SentVoiceError?)
    case muteChanged(Bool)
    case qualityWarning(QualityWarning)
    case error(SentVoiceError)
}

/// A call the client placed. Events arrive on the listeners in the order the provider reported them.
public final class Call: @unchecked Sendable, Identifiable {
    /// The provider's id for the call, which Sent's call records carry too.
    public let id: String
    public let direction: CallDirection
    public let from: Address
    public let to: Address
    public let startedAt: Date

    private let lock = NSLock()
    private var machine: CallStateMachine
    private var listeners: [UUID: @Sendable (CallEvent) -> Void] = [:]
    private var muted = false
    private var connectedAt: Date?
    private var endedAt: Date?
    private var endedWith: SentVoiceError?
    private let actions: Actions

    /// What the client lets a call do.
    struct Actions {
        let hangup: @Sendable () async throws -> Void
        let mute: @Sendable (Bool) throws -> Void
        let sendDigits: @Sendable (String) throws -> Void
        let stats: @Sendable () async throws -> CallStats
    }

    init(id: String, direction: CallDirection, from: Address, to: Address, startedAt: Date, actions: Actions) {
        self.id = id
        self.direction = direction
        self.from = from
        self.to = to
        self.startedAt = startedAt
        self.machine = CallStateMachine(direction: direction)
        self.actions = actions
    }

    public var state: CallState { lock.locked { machine.state } }
    public var isMuted: Bool { lock.locked { muted } }
    /// Set once the call reached `connected`.
    public var connectedTime: Date? { lock.locked { connectedAt } }
    /// Set once the call ended, with the error that ended it when there is one.
    public var endedTime: Date? { lock.locked { endedAt } }
    public var error: SentVoiceError? { lock.locked { endedWith } }

    /// Listens to the call's events until the token is cancelled or the call ends.
    @discardableResult
    public func on(_ listener: @escaping @Sendable (CallEvent) -> Void) -> ListenerToken {
        let id = UUID()
        lock.locked { listeners[id] = listener }
        return ListenerToken { [weak self] in self?.lock.locked { _ = self?.listeners.removeValue(forKey: id) } }
    }

    public func hangup() async throws {
        guard !state.isTerminal else { return }
        try await actions.hangup()
    }

    public func mute(_ muted: Bool) throws {
        try actions.mute(muted)
    }

    /// Sends DTMF digits: `0`-`9`, `*`, `#`, `A`-`D`, and `,` for a pause.
    public func sendDigits(_ digits: String) throws {
        let allowed = Set("0123456789*#ABCDabcd,")
        guard !digits.isEmpty, digits.allSatisfy(allowed.contains) else {
            throw SentVoiceError(code: .invalidAddress, message: "Digits may be 0-9, *, #, A-D and , for a pause.")
        }
        try actions.sendDigits(digits)
    }

    public func stats() async throws -> CallStats {
        try await actions.stats()
    }

    /// Applies what the provider reported. Returns the event to emit, or nil when the contract refuses the move.
    func apply(_ event: AdapterCallEvent, at now: Date) -> CallEvent? {
        let out: CallEvent? = lock.locked {
            switch event {
            case .ringing: return machine.transition(to: .ringing) ? .ringing : nil
            case .answered: return machine.transition(to: .answered) ? .answered : nil
            case .connected:
                guard machine.transition(to: .connected) else { return nil }
                if connectedAt == nil { connectedAt = now }
                return .connected
            case .reconnecting: return machine.transition(to: .reconnecting) ? .reconnecting : nil
            case .reconnected: return machine.transition(to: .connected) ? .reconnected : nil
            case .disconnected(let state, let error):
                guard state.isTerminal, machine.transition(to: state) else { return nil }
                endedAt = now
                endedWith = error
                return .disconnected(state: state, error: error)
            case .muteChanged(let value):
                muted = value
                return .muteChanged(value)
            case .qualityWarning(let warning): return .qualityWarning(warning)
            case .error(let error): return .error(error)
            }
        }
        if let out { emit(out) }
        return out
    }

    private func emit(_ event: CallEvent) {
        let current = lock.locked { Array(listeners.values) }
        for listener in current { listener(event) }
        if case .disconnected = event { lock.locked { listeners.removeAll() } }
    }
}

/// Cancels a listener when deinitialised or cancelled.
public final class ListenerToken: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (() -> Void)?

    init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }

    public func cancel() {
        let action = lock.locked { () -> (() -> Void)? in
            defer { onCancel = nil }
            return onCancel
        }
        action?()
    }

    deinit { cancel() }
}

extension NSLock {
    func locked<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
