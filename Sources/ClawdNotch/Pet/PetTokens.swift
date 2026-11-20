// PetTokens.swift
// The design tokens from docs/07: every colour of the pet and the island, defined once.

import CoreGraphics

/// Colour and size tokens (docs/07-pet-design.md). A colour literal anywhere else is a review finding.
enum PetTokens {
    static let body = rgb(0xD97757)
    static let bodyShade = rgb(0xC2643F)
    static let eye = rgb(0x1F1A17)
    static let badgeAlert = rgb(0xFF3B30)
    /// The "!" glyph on the alert badge.
    static let badgeGlyph = rgb(0xFFFFFF)
    /// Speech bubble, thought cloud and "Zzz".
    static let bubbleFill = rgb(0xFFFFFF, alpha: 0.92)
    static let hpHigh = rgb(0x34C759)
    static let hpMid = rgb(0xFFCC00)
    static let hpLow = rgb(0xFF3B30)
    static let islandBackground = rgb(0x000000)

    /// The anatomy's unit box (width × height); all pet geometry is in these units, origin bottom-left.
    static let unitBox = CGSize(width: 32, height: 24)
    /// Default pet height in the collapsed island, in points.
    static let collapsedHeight: CGFloat = 26

    private static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
