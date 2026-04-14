//  EmptyStateView.swift
//  HomeBase
//  Full-page and inline empty state components.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

// MARK: - EmptyStateView (full page)
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String?   = nil
    var buttonAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.homeBaseGreen.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: icon)
                    .font(.system(size: 42))
                    .foregroundColor(.homeBaseGreen.opacity(0.6))
            }
            VStack(spacing: 8) {
                Text(title)
                    .font(.title3).bold()
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if let buttonTitle, let buttonAction {
                PrimaryButton(title: buttonTitle, action: buttonAction)
                    .padding(.horizontal, 48)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - InlineEmptyState (compact, used inside cards)
struct InlineEmptyState: View {
    let icon: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.homeBaseGreen.opacity(0.6))
                .font(.subheadline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - AllClearView — shown when everything is done
struct AllClearView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.homeBaseGreen)
            Text(message)
                .font(.subheadline).bold()
                .foregroundColor(.homeBaseGreen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
