// PetDemo.swift
// Debug-only state cycler for screenshots and perf checks: launch with `--pet-demo` (WP-3).

import ClawdCore

/// Cycles a `PetView` through every `PetState` every 3 s when the app runs with `--pet-demo`.
/// Compiles to a no-op in release builds.
@MainActor
enum PetDemo {
    static func startIfRequested(on view: PetView) {
        #if DEBUG
        PoseRenderer.runIfRequested()
        guard CommandLine.arguments.contains("--pet-demo") else { return }
        Task {
            for step in 0... {
                let state = PetState.allCases[step % PetState.allCases.count]
                view.setState(state)
                if state == .done || state == .needsInput { view.popOut() }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        #endif
    }
}
