//  View+Modifiers.swift
//  Hemvo
//  Custom SwiftUI view modifiers and convenience extensions.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import Foundation
internal import Combine
internal import UserNotifications

// MARK: - Card Modifier
struct CardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var shadowRadius: CGFloat = 6
    var shadowY: CGFloat      = 2

    func body(content: Content) -> some View {
        content
            .background(Color(.systemBackground))
            .cornerRadius(cornerRadius)
            .shadow(color: .black.opacity(0.05), radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 16,
                   shadowRadius: CGFloat = 6,
                   shadowY: CGFloat = 2) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius,
                              shadowRadius: shadowRadius,
                              shadowY: shadowY))
    }
}

// MARK: - Page Background
struct PageBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            Color.homeBaseBackground.ignoresSafeArea()
            content
        }
    }
}

extension View {
    func pageBackground() -> some View {
        modifier(PageBackgroundModifier())
    }
}

// MARK: - Rounded Button Style
struct HBButtonStyle: ButtonStyle {
    var color: Color    = .homeBaseGreen
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).bold()
            .frame(maxWidth: .infinity)
            .padding()
            .background(isDestructive ? Color.red : color)
            .foregroundColor(.white)
            .cornerRadius(14)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    func hbButtonStyle(color: Color = .homeBaseGreen, isDestructive: Bool = false) -> some View {
        self.buttonStyle(HBButtonStyle(color: color, isDestructive: isDestructive))
    }
}

// MARK: - Shake Modifier (for error feedback)
struct ShakeModifier: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit   = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)), y: 0)
        )
    }
}

extension View {
    func shake(trigger: CGFloat) -> some View {
        modifier(ShakeModifier(animatableData: trigger))
    }
}

// MARK: - Conditional Modifier
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Hide Keyboard
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// MARK: - Loading Overlay
struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    let message: String

    func body(content: Content) -> some View {
        ZStack {
            content.disabled(isLoading)
            if isLoading {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.4).tint(.white)
                    Text(message).font(.subheadline).foregroundColor(.white)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }
        }
    }
}

extension View {
    func loadingOverlay(isLoading: Bool, message: String = "Loading…") -> some View {
        modifier(LoadingOverlay(isLoading: isLoading, message: message))
    }
}
