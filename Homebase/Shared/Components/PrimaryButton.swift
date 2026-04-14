//  PrimaryButton.swift
//  HomeBase
//  Branded button components used throughout the app.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

// MARK: - PrimaryButton
struct PrimaryButton: View {
    let title: String
    var icon: String?        = nil
    var isLoading: Bool      = false
    var isDisabled: Bool     = false
    var color: Color         = .homeBaseGreen
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    if let icon {
                        Image(systemName: icon)
                    }
                    Text(title).font(.headline).bold()
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isDisabled ? Color(.systemGray4) : color)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(isLoading || isDisabled)
    }
}

// MARK: - SecondaryButton
struct SecondaryButton: View {
    let title: String
    var icon: String?   = nil
    var color: Color    = .homeBaseGreen
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.subheadline).bold()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(14)
        }
    }
}

// MARK: - DestructiveButton
struct DestructiveButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.subheadline).bold()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .cornerRadius(14)
        }
    }
}

// MARK: - IconButton
struct IconButton: View {
    let icon: String
    var color: Color     = .homeBaseGreen
    var size: CGFloat    = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(color)
                .frame(width: size, height: size)
                .background(color.opacity(0.12))
                .clipShape(Circle())
        }
    }
}

// MARK: - PillButton
struct PillButton: View {
    let title: String
    var isSelected: Bool = false
    var color: Color     = .homeBaseGreen
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption).bold()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? color : Color(.systemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        }
    }
}
