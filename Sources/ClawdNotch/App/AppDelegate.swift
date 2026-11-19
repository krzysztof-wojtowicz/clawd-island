// AppDelegate.swift
// Owns the app's long-lived objects and wires them together at launch.

import AppKit

/// Application lifecycle owner. It holds the notch window controller and the pet for the life of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private let pet = PetView(frame: .zero)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchWindowController()
        let slot = controller.island.petSlot
        pet.frame = slot.bounds
        pet.autoresizingMask = [.width, .height]
        slot.addSubview(pet)
        PetDemo.startIfRequested(on: pet)
        notchController = controller
        pausePetWhileUnseen()
    }

    /// Freezes the pet's loops while the screen sleeps or the user session is switched away (docs/08 rule 4).
    private func pausePetWhileUnseen() {
        let center = NSWorkspace.shared.notificationCenter
        let pauses: [(Notification.Name, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.sessionDidResignActiveNotification, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, false),
        ]
        for (name, paused) in pauses {
            center.addObserver(forName: name, object: nil, queue: .main) { [pet] _ in
                MainActor.assumeIsolated { pet.setPaused(paused) }
            }
        }
    }
}
