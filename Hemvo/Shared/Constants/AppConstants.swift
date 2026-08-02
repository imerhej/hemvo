//  AppConstants.swift
//  Hemvo
//  Global constants used across the app.

internal import Foundation

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

    /// App Store Connect Apple ID for Hemvo.
    static let appStoreID         = "6764900837"
    static let appStoreURL        = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
    /// Opens the App Store listing with the "Write a Review" sheet already presented.
    static let appStoreReviewURL  = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!

    // MARK: - Dashboard
    static let dashboardPreviewCount = 3     // rows shown in dashboard section cards

    // MARK: - Calendar Strip
    static let calendarStripPastDays   = 3
    static let calendarStripTotalDays  = 14

    // MARK: - Maintenance
    static let maintenanceDueSoonDays  = 7   // "due soon" threshold in days

    // MARK: - Recurring Bills
    /// Periods ahead of a series' anchor we search when resolving the next due date.
    /// 600 covers ~11 years of a weekly bill — far past any realistic gap.
    static let recurrenceMaxLookaheadSteps = 600
    /// Occurrences the catch-up sweep will mint for one series in a single pass, so a
    /// bill back-dated by years can't spawn hundreds of rows on first sync.
    static let recurrenceMaxCatchUp        = 24
}
