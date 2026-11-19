// NotchGeometry.swift
// Computes where the (physical or virtual) notch sits on a screen, from plain screen metrics.

import CoreGraphics

/// The notch area in AppKit screen coordinates (origin bottom-left).
public struct NotchRect: Equatable, Sendable {
    public let frame: CGRect
    /// `false` when the screen has no notch and we draw a virtual one.
    public let isPhysical: Bool

    public init(frame: CGRect, isPhysical: Bool) {
        self.frame = frame
        self.isPhysical = isPhysical
    }
}

/// Pure notch math, kept out of AppKit so it can be unit-tested (docs/06-window-and-notch.md).
public enum NotchGeometry {
    static let virtualWidth: CGFloat = 200
    static let minVirtualHeight: CGFloat = 24

    /// Returns the notch rectangle for a screen.
    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`.
    ///   - visibleFrame: `NSScreen.visibleFrame`, used to infer the menu bar height for a virtual notch.
    ///   - safeTop: `NSScreen.safeAreaInsets.top`; greater than 0 only on notched displays.
    ///   - auxLeft: Width of `auxiliaryTopLeftArea`, if any.
    ///   - auxRight: Width of `auxiliaryTopRightArea`, if any.
    public static func compute(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeTop: CGFloat,
        auxLeft: CGFloat?,
        auxRight: CGFloat?
    ) -> NotchRect {
        if safeTop > 0, let auxLeft, let auxRight {
            let width = screenFrame.width - auxLeft - auxRight
            let frame = CGRect(x: screenFrame.minX + auxLeft, y: screenFrame.maxY - safeTop, width: width, height: safeTop)
            return NotchRect(frame: frame, isPhysical: true)
        }
        // An auto-hidden menu bar leaves no gap above visibleFrame, hence the minimum height.
        let height = max(screenFrame.maxY - visibleFrame.maxY, minVirtualHeight)
        let frame = CGRect(
            x: screenFrame.midX - virtualWidth / 2,
            y: screenFrame.maxY - height,
            width: virtualWidth,
            height: height
        )
        return NotchRect(frame: frame, isPhysical: false)
    }
}
