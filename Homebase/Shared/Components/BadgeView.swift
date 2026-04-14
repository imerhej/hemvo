//  BadgeView.swift
//  HomeBase
//  Status, category, and priority badge components.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

// MARK: - BadgeView
struct BadgeView: View {
    let text: String
    var color: Color  = .homeBaseGreen
    var style: Style  = .filled

    enum Style { case filled, outlined, subtle }

    var body: some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background)
            .foregroundColor(foreground)
            .cornerRadius(6)
    }

    private var background: Color {
        switch style {
        case .filled:   return color
        case .outlined: return .clear
        case .subtle:   return color.opacity(0.15)
        }
    }

    private var foreground: Color {
        switch style {
        case .filled:   return .white
        case .outlined: return color
        case .subtle:   return color
        }
    }
}

// MARK: - PriorityBadge
struct PriorityBadge: View {
    let priority: HouseTask.Priority

    var body: some View {
        BadgeView(text: priority.label, color: priority.displayColor, style: .subtle)
    }
}

// MARK: - MealTypeBadge
struct MealTypeBadge: View {
    let mealType: Meal.MealType

    var color: Color {
        switch mealType {
        case .breakfast: return .orange
        case .lunch:     return .green
        case .dinner:    return .blue
        case .snack:     return .purple
        }
    }

    var body: some View {
        BadgeView(text: mealType.label, color: color, style: .subtle)
    }
}

// MARK: - StatusDot
struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - OverdueBadge
struct OverdueBadge: View {
    var body: some View {
        BadgeView(text: "OVERDUE", color: .red, style: .filled)
    }
}

// MARK: - CountBadge (notification-style)
struct CountBadge: View {
    let count: Int
    var color: Color = .red

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2).bold()
                .foregroundColor(.white)
                .padding(.horizontal, count > 9 ? 5 : 6)
                .padding(.vertical, 3)
                .background(color)
                .clipShape(Capsule())
        }
    }
}
