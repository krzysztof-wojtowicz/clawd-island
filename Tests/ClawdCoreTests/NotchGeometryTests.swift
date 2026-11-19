// NotchGeometryTests.swift
// Verifies physical and virtual notch placement (REQ-01).

import CoreGraphics
import Testing
@testable import ClawdCore

@Suite("NotchGeometry")
struct NotchGeometryTests {
    /// One screen configuration and the notch it must produce.
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let screen: CGRect
        let visible: CGRect
        let safeTop: CGFloat
        let auxLeft: CGFloat?
        let auxRight: CGFloat?
        let expected: NotchRect
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "built-in notch, 14-inch default scaling",
             screen: CGRect(x: 0, y: 0, width: 1512, height: 982),
             visible: CGRect(x: 0, y: 0, width: 1512, height: 944),
             safeTop: 32, auxLeft: 657, auxRight: 657,
             expected: NotchRect(frame: CGRect(x: 657, y: 950, width: 198, height: 32), isPhysical: true)),
        Case(name: "built-in notch on a non-primary screen left of the main one",
             screen: CGRect(x: -1512, y: 0, width: 1512, height: 982),
             visible: CGRect(x: -1512, y: 0, width: 1512, height: 944),
             safeTop: 32, auxLeft: 663, auxRight: 664,
             expected: NotchRect(frame: CGRect(x: -849, y: 950, width: 185, height: 32), isPhysical: true)),
        Case(name: "external display gets a centred virtual notch of menu bar height",
             screen: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
             visible: CGRect(x: 1512, y: 0, width: 2560, height: 1415),
             safeTop: 0, auxLeft: nil, auxRight: nil,
             expected: NotchRect(frame: CGRect(x: 2692, y: 1415, width: 200, height: 25), isPhysical: false)),
        Case(name: "auto-hidden menu bar falls back to the minimum height",
             screen: CGRect(x: 0, y: 0, width: 1920, height: 1080),
             visible: CGRect(x: 0, y: 0, width: 1920, height: 1080),
             safeTop: 0, auxLeft: nil, auxRight: nil,
             expected: NotchRect(frame: CGRect(x: 860, y: 1056, width: 200, height: 24), isPhysical: false)),
        Case(name: "safe-area inset without auxiliary areas is treated as no notch",
             screen: CGRect(x: 0, y: 0, width: 1920, height: 1080),
             visible: CGRect(x: 0, y: 0, width: 1920, height: 1055),
             safeTop: 25, auxLeft: nil, auxRight: nil,
             expected: NotchRect(frame: CGRect(x: 860, y: 1055, width: 200, height: 25), isPhysical: false)),
    ]

    @Test("Notch placement", arguments: cases)
    func placement(_ c: Case) {
        let rect = NotchGeometry.compute(
            screenFrame: c.screen, visibleFrame: c.visible, safeTop: c.safeTop, auxLeft: c.auxLeft, auxRight: c.auxRight
        )
        #expect(rect == c.expected)
    }
}
