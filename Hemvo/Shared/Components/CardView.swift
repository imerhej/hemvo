//  CardView.swift
//  Hemvo
//  Reusable card container with optional header and action button.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

// MARK: - CardView
struct CardView<Content: View>: View {
    var title: String?
    var icon: String?
    var iconColor: Color = .homeBaseGreen
    var actionLabel: String?
    var action: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Optional header
            if let title {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundColor(iconColor)
                            .font(.subheadline)
                    }
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if let actionLabel, let action {
                        Button(actionLabel, action: action)
                            .font(.subheadline)
                            .foregroundColor(.homeBaseGreen)
                    }
                }
            }
            content()
        }
        .padding()
        .cardStyle()
    }
}

// MARK: - StatCard — single numeric stat
struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    var destination: AnyView? = nil

    var body: some View {
        Group {
            if let dest = destination {
                NavigationLink(destination: dest) { cardBody }
            } else {
                cardBody
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Spacer()
            Text(value)
                .font(.headline).bold()
                .foregroundColor(.primary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - InfoRow — label + value in a horizontal row
struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline).bold()
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - DividerRow
struct DividerRow: View {
    var body: some View {
        Divider().padding(.vertical, 2)
    }
}
