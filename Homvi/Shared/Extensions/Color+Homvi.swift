//  Color+Homvi.swift
//  Homvi
//  Brand color palette and hex initializer.

internal import SwiftUI


// MARK: - Brand Colors
extension Color {
    /// Primary green  — #4CAF74  (add to Assets.xcassets as "HomviGreen")
    static let homeBaseGreen      = Color("HomviGreen")

    /// Page background — #F5F7F2  (add to Assets.xcassets as "HomviBackground")
    static let homeBaseBackground = Color("HomviBackground")

    /// Dark accent     — #2E7D52  (add to Assets.xcassets as "HomviAccent")
    static let homeBaseAccent     = Color("HomviAccent")

    // MARK: - Fallbacks (used when asset catalog isn't set up yet)
    static let hbGreenFallback      = Color(hex: "#4CAF74")!
    static let hbBackgroundFallback = Color(hex: "#F5F7F2")!
    static let hbAccentFallback     = Color(hex: "#2E7D52")!
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


