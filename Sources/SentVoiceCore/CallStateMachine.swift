/// Tracks a call's state and refuses the moves the contract does not allow.
public struct CallStateMachine: Sendable, Equatable {
    public private(set) var state: CallState

    public init(direction: CallDirection) {
        state = CallState.initial(for: direction)
    }

    /// Moves to `next` when the contract allows it. Returns whether it did.
    @discardableResult
    public mutating func transition(to next: CallState) -> Bool {
        guard state.canTransition(to: next) else { return false }
        state = next
        return true
    }
}
