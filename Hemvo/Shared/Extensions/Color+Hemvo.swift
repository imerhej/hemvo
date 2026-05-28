//  Color+Hemvo.swift
//  Hemvo
//  Brand color palette and hex initializer.

internal import SwiftUI


// MARK: - Brand Colors
extension Color {
    static let homeBaseGreen      = Color("HemvoGreen")
    static let homeBaseBackground = Color("HemvoBackground")
    static let homeBaseAccent     = Color("HemvoAccent")
}

// MARK: - Hex Initializer
extension Color {
    /// Initialize a Color from a CSS-style hex string: "#RRGGBB" or "RRGGBB".
    init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >>  8) & 0xFF) / 255.0,
            blue:  Double( value        & 0xFF) / 255.0
        )
    }
}


