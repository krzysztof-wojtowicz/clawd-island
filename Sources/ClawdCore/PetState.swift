// PetState.swift
// The single aggregate state the pet renders (docs/04-state-machine.md).

/// What the pet shows, derived from all live sessions. Ordered from calmest to most urgent.
public enum PetState: String, CaseIterable, Equatable, Sendable {
    case sleeping
    case idle
    case thinking
    case talking
    case done
    case needsInput
}
