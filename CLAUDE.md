# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Rename note:** The app was previously called **Homebase**, then **Homvi**, and has been renamed to **Hemvo**. The source folder is `Hemvo/`, the project file is `Homvi.xcodeproj`, and the bundle ID is `com.issammerhej.Hemvo`. Legacy UserDefaults keys still use the `hb_` prefix (e.g. `hb_meals`, `hb_events`) — these are intentional carry-overs and should be migrated to `hemvo_` at a later point.

## Build & Run

This is an Xcode project — all building and testing is done through Xcode or `xcodebuild`.

```bash
# Build from CLI (simulator)
xcodebuild -project "Homvi.xcodeproj" -scheme "Hemvo" -destination "platform=iOS Simulator,name=iPhone 16" build

# Run all tests
xcodebuild -project "Homvi.xcodeproj" -scheme "Hemvo" -destination "platform=iOS Simulator,name=iPhone 16" test

# Run a single test file (example)
xcodebuild -project "Homvi.xcodeproj" -scheme "Hemvo" -destination "platform=iOS Simulator,name=iPhone 16" test -only-testing:HemvoTests/AuthViewModelTests
```

- **Bundle ID:** `com.issammerhej.Hemvo`
- **Deployment target:** iOS 26.2
- **Swift version:** 5.0
- **Test targets:** `HemvoTests`, `HemvoUITests`
- Tests use **Swift Testing** (not XCTest) — use `@Test` and `#expect` macros

## Architecture

MVVM with a service layer. The three-layer stack:

1. **Models** (`Hemvo/Core/Models/`) — Plain structs, all `Codable`. No business logic.
2. **ViewModels** (`Hemvo/Core/ViewModels/`) — `@MainActor ObservableObject` classes. Call services, expose `@Published` state to views.
3. **Services** (`Hemvo/Core/Services/`) — Singletons managing persistence, auth, notifications, subscriptions, etc.

Views get ViewModels via `@EnvironmentObject` injected at the root in `HemvoApp.swift`.

### Navigation

```
HemvoApp
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

Deep links (`hemvo://reset-password?token=XXX`) are handled in `HemvoApp.onOpenURL` and present `ResetPasswordView` full-screen.

### Data Persistence

- **Supabase (PostgreSQL)** — primary backend for all user, household, and app data. Client configured in `Hemvo/SupabaseClient.swift` with certificate pinning and Keychain session storage. Credentials live in `Hemvo/AppSecrets.swift` (not committed).
- **CoreData + NSPersistentCloudKitContainer** — local structured data via `PersistenceService`. CloudKit sync is disabled; the container is kept for offline caching.
- **UserDefaults** — ViewModel-level caches (e.g. `hb_meals`, `hb_events`) and household data (`hb_household_v2`). All keys still use the legacy `hb_` prefix — migrate to `hemvo_` at a later point.
- **UserPreferences** — `@MainActor` singleton that syncs five preference keys (notification toggles + avatar color) between `UserDefaults` and `NSUbiquitousKeyValueStore` (iCloud KV). Replaces the old `CloudSyncService`.
- **Keychain** — Supabase auth session token stored via `KeychainHelper` through a custom `KeychainAuthStorage` adapter (see `SupabaseClient.swift`).

### Authentication

Managed by `AuthViewModel` + `AuthService` / `SocialAuthService`. All paths ultimately resolve to a Supabase session.

| Path | Mechanism |
|------|-----------|
| Email/password | `AuthService` → Supabase Auth; `login()` accepts email **or** username (resolves username→email via `profiles` table) |
| Sign up | `AuthService.createAccount()` → `create-account` Edge Function (uses admin API to avoid GoTrue SMTP issues) |
| Sign in with Apple | `ASAuthenticationServices` via `SocialAuthService` |
| Google Sign-In | `GoogleSignIn` SDK, loaded dynamically via `NSClassFromString` |
| Biometrics | `LocalAuthentication` (Face ID / Touch ID), enabled after first login |
| Password reset | `send-password-reset-email` Edge Function → deep link `hemvo://reset-password?token=XXX` → `ResetPasswordView` |
| Change password | `change_user_password` Supabase RPC (SECURITY DEFINER, avoids OTP reauthentication requirement) |

### Subscriptions

StoreKit 2 via `StoreKitService`. Two products:
- `com.hemvo.app.subscription.monthly` — $7.99/mo
- `com.hemvo.app.subscription.annual` — $49.99/yr

New users get a 7-day free trial (`AppConstants.trialDurationDays`). After trial, `PaywallView` gates access until a purchase is verified. Subscription status is mirrored to Supabase `profiles.subscription_status` so household members on other devices can read it without StoreKit access.

### Services Reference

| Service | Location | Responsibility |
|---------|----------|----------------|
| `AuthService` | `Core/Services/` | Supabase Auth: login (email/username), sign-up, profile CRUD, subscription status sync |
| `SocialAuthService` | `Core/Services/` | Apple & Google OAuth |
| `StoreKitService` | `Core/Services/` | In-app purchases, subscription verification |
| `HouseholdService` | `Features/HouseHold/` | `@MainActor` singleton; manages household state, members, invites, Supabase Realtime subscriptions |
| `PersistenceService` | `Core/Services/` | CoreData stack; use `.preview` for SwiftUI previews |
| `UserPreferences` | `Core/Services/` | iCloud KV + UserDefaults sync for notification prefs and avatar color |
| `PushNotificationService` | `Core/Services/` | Registers APNs tokens to `device_tokens` Supabase table; calls `notify-household` Edge Function |
| `NotificationService` | `Core/Services/` | Local push notifications (bills, maintenance, meals, trial expiry) |
| `HouseholdInviteService` | `Core/Services/` | Invite codes, 7-day expiry, email dispatch |
| `EmailService` | `Core/Services/` | Transactional email via Resend API (API key inside the service) |
| `PasswordResetService` | `Core/Services/` | Legacy token generation/validation — superseded by Supabase Edge Function flow |
| `CertificatePinner` | `Core/Services/` | SPKI-hash TLS pinning for all Supabase traffic; update hashes before cert expiry (Jul 2026) |
| `KeychainHelper` | `Core/Services/` | Keychain read/write/delete; used by `KeychainAuthStorage` for Supabase session tokens |

### Supabase Edge Functions

Deployed under `supabase/functions/`. All are invoked via `supabase.functions.invoke(...)`.

| Function | Trigger | Purpose |
|----------|---------|---------|
| `create-account` | Sign-up | Creates auth user via admin API + inserts profile; sends confirmation email via Resend |
| `delete-member` | Household owner action | Removes a member from the household |
| `notify-household` | Content create/update | Sends APNs push to household members via device_tokens table |
| `process-scheduled-push` | pg_cron (scheduled) | Processes `notification_schedule` table entries and sends timed pushes |
| `send-confirmation-email` | Account creation | Resend email for account verification |
| `send-invite-email` | Household invite | Resend email with invite code |
| `send-password-changed-email` | Password change | Security alert email after password update |
| `send-password-reset-email` | Forgot password | Generates Supabase recovery link and sends via Resend |

### External Integrations

- **Supabase** — auth, PostgreSQL database, Realtime subscriptions, Edge Functions, and APNs push pipeline. Credentials (`supabaseURL`, `supabaseAnonKey`) in `AppSecrets.swift` — do not commit.
- **Resend API** — transactional email (confirmation, password reset, invites). API key is in `EmailService.swift` — move to Supabase secrets / a secrets manager before production.
- **Apple Push Notification service (APNs)** — push delivery. Required Supabase secrets: `APNS_KEY_ID` (key VBY93G9JH7), `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`. Debug builds use sandbox; release/TestFlight use production.
- **App Store Connect** — StoreKit product IDs must exist in ASC before purchases work in production.
- **CloudKit** — container `iCloud.com.hemvo.app`; entitlements differ between Debug (`Hemvo.entitlements`) and Release (`HemvoRelease.entitlements`). Sync is currently disabled.

## Key Conventions

- All ViewModels are `@MainActor` — do not dispatch to main manually inside them.
- Use `async/await` throughout; avoid callbacks except when wrapping legacy APIs (use `withCheckedContinuation`).
- Feature views live in `Hemvo/Features/<FeatureName>/`. Shared UI components go in `Hemvo/Shared/Components/`.
- `AppConstants.swift` is the single source of truth for magic numbers (trial duration, pricing, dashboard row limits, etc.).
- `AppSecrets.swift` holds Supabase credentials — it is **not** committed to git. Copy `AppSecrets.swift.template` (if present) and fill in values locally.
- Supabase calls use the module-level `supabase` constant (defined in `Hemvo/SupabaseClient.swift`) — never create a second client.
- `HouseholdService.shared` is `@MainActor` — always read it from the main actor (use `await MainActor.run { ... }` from background contexts).
- `AuthService` methods that call `supabase.auth.session` are `nonisolated` — calling them from the main actor can cause deadlocks on token refresh.
- SwiftUI previews use `PersistenceService.preview` (in-memory CoreData) and inject mock environment objects.
- Certificate pins in `CertificatePinner.swift` expire **July 2026** — update with `scripts/update-pins.sh` at least 30 days before expiry.
