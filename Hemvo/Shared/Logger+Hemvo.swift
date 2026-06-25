// Logger+Hemvo.swift
// Hemvo
//
// Structured os.log loggers scoped per subsystem.
// Use .private for any PII (emails, names, IDs) so values are
// redacted in system logs on non-developer devices.

internal import OSLog

extension Logger {
    private static let subsystem = "com.issamnmerhej.Hemvo"

    static let auth        = Logger(subsystem: subsystem, category: "Auth")
    static let push        = Logger(subsystem: subsystem, category: "Push")
    static let supabase    = Logger(subsystem: subsystem, category: "Supabase")
    static let household   = Logger(subsystem: subsystem, category: "Household")
    static let email       = Logger(subsystem: subsystem, category: "Email")
    static let deepLink    = Logger(subsystem: subsystem, category: "DeepLink")
    static let realtime    = Logger(subsystem: subsystem, category: "Realtime")
    static let notif       = Logger(subsystem: subsystem, category: "Notifications")
    static let store       = Logger(subsystem: subsystem, category: "StoreKit")
    static let grocery     = Logger(subsystem: subsystem, category: "Grocery")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let prefs       = Logger(subsystem: subsystem, category: "Preferences")
    static let shopping    = Logger(subsystem: subsystem, category: "Shopping")
    static let budget      = Logger(subsystem: subsystem, category: "Budget")
    static let meals       = Logger(subsystem: subsystem, category: "Meals")
    static let schedule    = Logger(subsystem: subsystem, category: "Schedule")
    static let maintenance = Logger(subsystem: subsystem, category: "Maintenance")
}
