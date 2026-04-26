//  StoreIDs.swift
//  Homvi
//  StoreKit 2 product identifiers — must match App Store Connect exactly.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

enum StoreIDs {
    /// $7.99 / month auto-renewing subscription
    static let monthly = "com.homvi.app.subscription.monthly"

    /// $59.99 / year auto-renewing subscription
    static let annual  = "com.homvi.app.subscription.annual"

    /// All subscription product IDs (used for Product.products(for:))
    static let all: Set<String> = [monthly, annual]
}
