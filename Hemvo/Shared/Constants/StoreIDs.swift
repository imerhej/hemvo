//  StoreIDs.swift
//  Hemvo
//  StoreKit 2 product identifiers — must match App Store Connect exactly.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import Foundation
internal import Combine
internal import UserNotifications

// Changing or adding an id here REQUIRES adding it to KNOWN_PRODUCT_IDS in
// supabase/functions/verify-subscription/index.ts and redeploying that function.
// The server rejects unknown product ids as `active:false`, which the app treats
// as "Apple says this purchase is invalid" and downgrades the owner to expired.
enum StoreIDs {
    /// $4.99 / month auto-renewing subscription
    /// Note: the original `com.hemvo.app.sub.monthly` was deleted in App Store
    /// Connect and its product ID is permanently reserved by Apple, so this new
    /// ID replaces it. Must match the recreated subscription in ASC exactly.
    static let monthly = "com.hemvo.app.sub.monthly1"

    /// $49.99 / year auto-renewing subscription
    static let annual  = "com.hemvo.app.sub.annual"

    /// All subscription product IDs (used for Product.products(for:))
    static let all: Set<String> = [monthly, annual]
}
