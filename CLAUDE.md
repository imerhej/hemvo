# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Rename note:** The app was previously called **Homebase**. It has been renamed to **Homvi**. The source folder is `Homvi/`, the project file is `Homvi.xcodeproj`, and the bundle ID is `com.issammerhej.Homvi`. Legacy UserDefaults keys still use the `hb_` prefix (e.g. `hb_meals`, `hb_events`) — these are intentional carry-overs and should be migrated to `homvi_` at a later point.

## Build & Run

This is an Xcode project — all building and testing is done through Xcode or `xcodebuild`.

```bash
# Build from CLI (simulator)
xcodebuild -project "Homvi.xcodeproj" -scheme "Homvi" -destination "platform=iOS Simulator,name=iPhone 16" build

# Run all tests
xcodebuild -project "Homvi.xcodeproj" -scheme "Homvi" -destination "platform=iOS Simulator,name=iPhone 16" test

# Run a single test file (example)
xcodebuild -project "Homvi.xcodeproj" -scheme "Homvi" -destination "platform=iOS Simulator,name=iPhone 16" test -only-testing:HomviTests/AuthViewModelTests
```

- **Bundle ID:** `com.issammerhej.Homvi`
- **Deployment target:** iOS 26.2
- **Swift version:** 5.0
- **Test targets:** `HomviTests`, `HomviUITests`
- Tests use **Swift Testing** (not XCTest) — use `@Test` and `#expect` macros

## Architecture

MVVM with a service layer. The three-layer stack:

1. **Models** (`Homvi/Core/Models/`) — Plain structs, all `Codable`. No business logic.
2. **ViewModels** (`Homvi/Core/ViewModels/`) — `@MainActor ObservableObject` classes. Call services, expose `@Published` state to views.
3. **Services** (`Homvi/Core/Services/`) — Singletons managing persistence, auth, notifications, subscriptions, etc.

Views get ViewModels via `@EnvironmentObject` injected at the root in `HomviApp.swift`.

### Navigation

```
HomviApp
└─ RootView
    ├─ !isLoggedIn      → OnboardingView (login / signup / password reset)
    ├─ !subscriptionActive → PaywallView
    └─ subscribed       → ContentView (5-tab shell with LiquidTabBar)
         ├─ Dashboard
         ├─ Meals
         ├─ Budget
         ├─ Schedule
         └─ Maintenance
```

Deep links (`homvi://reset-password?token=XXX`) are handled in `HomviApp.onOpenURL` and present `ResetPasswordView` full-screen.

### Data Persistence

- **CoreData + NSPersistentCloudKitContainer** for structured app data (`PersistenceService`)
- **UserDefaults** for session state (current user, trial end date, biometric flag) and ViewModel-level data (e.g. `hb_meals` key in `MealPlanViewModel`). Note: all UserDefaults keys still use the legacy `hb_` prefix from the old Homebase name.
- **CloudKit sync is disabled by default** — toggle `useCloudKit = false` in `CloudSyncService.swift`. Requires a paid Apple Developer account and entitlement setup to enable.

### Authentication

Three paths managed by `AuthViewModel` + `AuthService`/`SocialAuthService`:

| Path | Mechanism |
|------|-----------|
| Email/password | `AuthService` (UserDefaults-backed stub — wire to a real backend when ready) |
| Sign in with Apple | `ASAuthenticationServices` via `SocialAuthService` |
| Google Sign-In | `GoogleSignIn` SDK, loaded dynamically via `NSClassFromString` |
| Biometrics | `LocalAuthentication` (Face ID / Touch ID), enabled after first login |

### Subscriptions

StoreKit 2 via `StoreKitService`. Two products:
- `com.homvi.app.subscription.monthly` — $7.99/mo
- `com.homvi.app.subscription.annual` — $59.99/yr

New users get a 7-day free trial (`AppConstants.trialDurationDays`). After trial, `PaywallView` gates access until a purchase is verified.

### Services Reference

| Service | Responsibility |
|---------|----------------|
| `AuthService` | Email/password login, session persistence |
| `SocialAuthService` | Apple & Google OAuth |
| `StoreKitService` | In-app purchases, subscription verification |
| `PersistenceService` | CoreData stack; use `.preview` for SwiftUI previews |
| `CloudSyncService` | iCloud sync triggers (disabled by default) |
| `NotificationService` | Local push notifications (bills, maintenance, meals, trial expiry) |
| `PasswordResetService` | Token generation & validation for deep-link password reset |
| `HouseholdInviteService` | Invite codes, 7-day expiry, email dispatch |
| `EmailService` | Transactional email via Resend API (API key lives inside the service) |

### External Integrations

- **Resend API** — email delivery (verification, password reset). API key is hardcoded in `EmailService.swift` — move to a secrets manager before production.
- **App Store Connect** — StoreKit product IDs must exist in ASC before purchases work in production.
- **CloudKit** — container `iCloud.com.homvi.app`; entitlements differ between Debug (`Homvi.entitlements`) and Release (`HomviRelease.entitlements`).

## Key Conventions

- All ViewModels are `@MainActor` — do not dispatch to main manually inside them.
- Use `async/await` throughout; avoid callbacks except when wrapping legacy APIs (use `withCheckedContinuation`).
- Feature views live in `Homvi/Features/<FeatureName>/`. Shared UI components go in `Homvi/Shared/Components/`.
- `AppConstants.swift` is the single source of truth for magic numbers (trial duration, pricing, dashboard row limits, etc.).
- SwiftUI previews use `PersistenceService.preview` (in-memory CoreData) and inject mock environment objects.
