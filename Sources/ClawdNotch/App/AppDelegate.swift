// AppDelegate.swift
// Owns the app's long-lived objects and wires them together at launch.

import AppKit

/// Application lifecycle owner. It holds the notch window controller for the life of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notchController = NotchWindowController()
    }
}
