//  AppConstants.swift
//  Hemvo
//  Global constants used across the app.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

enum AppConstants {
    // MARK: - Trial & Grace Period
    static let trialDurationDays  = 7
    static let gracePeriodDays    = 5   // days members retain access after owner's sub lapses

    // MARK: - Pricing
    static let monthlyPrice       = 4.99
    static let annualPrice        = 49.99
    static let annualMonthlyCost  = annualPrice / 12   // ~$4.17/mo

    // MARK: - App Info
    static let appName            = "Hemvo"
    static let appVersion         = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.04"
    static let buildNumber        = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    // MARK: - URLs
    static let privacyPolicyURL   = URL(string: "https://hemvo.app/privacy.html")!
    static let termsOfServiceURL  = URL(string: "https://hemvo.app/terms.html")!
    static let supportURL         = URL(string: "https://hemvo.app/contact.html")!

    // MARK: - Dashboard
    static let dashboardPreviewCount = 3     // rows shown in dashboard section cards

    // MARK: - Calendar Strip
    static let calendarStripPastDays   = 3
    static let calendarStripTotalDays  = 14

    // MARK: - Maintenance
    static let maintenanceDueSoonDays  = 7   // "due soon" threshold in days
}
