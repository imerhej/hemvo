//  AppConstants.swift
//  Homvi
//  Global constants used across the app.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

enum AppConstants {
    // MARK: - Trial
    static let trialDurationDays  = 7

    // MARK: - Pricing
    static let monthlyPrice       = 8.99
    static let annualPrice        = 92.99
    static let annualMonthlyCost  = annualPrice / 12   // ~$5.00/mo

    // MARK: - App Info
    static let appName            = "Homvi"
    static let appVersion         = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.04"
    static let buildNumber        = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    // MARK: - URLs
    static let privacyPolicyURL   = URL(string: "https://webstitching.com/homviapp/")!
    static let termsOfServiceURL  = URL(string: "https://webstitching.com/homviapp/")!
    static let supportURL         = URL(string: "https://webstitching.com/homviapp/")!

    // MARK: - Dashboard
    static let dashboardPreviewCount = 3     // rows shown in dashboard section cards

    // MARK: - Calendar Strip
    static let calendarStripPastDays   = 3
    static let calendarStripTotalDays  = 14

    // MARK: - Maintenance
    static let maintenanceDueSoonDays  = 7   // "due soon" threshold in days
}
