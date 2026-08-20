# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Rename note:** The app was previously called **Homebase**, then **Homvi**, and has been renamed to **Hemvo**. The source folder is `Hemvo/`, the project file is `Hemvo.xcodeproj`, and the bundle ID is `com.issamnmerhej.Hemvo`. UserDefaults keys have been migrated from the legacy `hb_` prefix to `hemvo_` (handled by `UserDefaultsMigration.swift` on first launch after the migration release).

## Build & Run

This is an Xcode project — all building and testing is done through Xcode or `xcodebuild`.

```bash
# Build from CLI (simulator)
xcodebuild -project "Hemvo.xcodeproj" -scheme "Hemvo" -destination "platform=iOS Simulator,name=iPhone 17" build

# Run all tests
xcodebuild -project "Hemvo.xcodeproj" -scheme "Hemvo" -destination "platform=iOS Simulator,name=iPhone 17" test

# Run a single test file (example)
xcodebuild -project "Hemvo.xcodeproj" -scheme "Hemvo" -destination "platform=iOS Simulator,name=iPhone 17" test -only-testing:HemvoTests/AuthViewModelTests
```

- **Bundle ID:** `com.issamnmerhej.Hemvo`
- **Deployment target:** iOS 18.6
- **Swift version:** 5.0
- **Device family:** iPhone only (`TARGETED_DEVICE_FAMILY = 1`)
- **Test targets:** `HemvoTests`, `HemvoUITests`
- Unit tests use **Swift Testing** (`@Test` / `#expect`); UI tests in `HemvoUITests` are XCTest (`XCUIApplication`)

### Versioning & Release

- `MARKETING_VERSION` in `project.pbxproj` is the source of truth for the version. Bump it with `./scripts/bump-version.sh [major|minor|patch]` — **never** `agvtool new-marketing-version`, which truncates `project.pbxproj` to zero bytes (see the script header).
- Build number is `CURRENT_PROJECT_VERSION` (Apple Generic versioning), incremented by `xcrun agvtool next-version -all` in the scheme's **Archive pre-action**. It must not run mid-build — the `Version + Build Number (agvtool)` build phase only stamps the built product's `Info.plist` with the current values.
- Approved App Store trains are closed, so `MARKETING_VERSION` must be bumped for every new submission.

### Test Files

| Target | File | Notes |
|--------|------|-------|
| `HemvoTests` | `ViewModelTests/{Auth,Budget,MealPlan}ViewModelTests`, `RecurringBillTests`, `SubscriptionDecisionTests` | Swift Testing |
| `HemvoUITests` | `BillCardLayoutUITests`, `BillClassificationUITests`, `InviteeScopeUITests`, `ChangePasswordFlowUITests`, `ResetPasswordFlowUITests` | XCTest |
| `HemvoUITests` | `AppStoreScreenshotUITests` | Env-gated on `SHOT_EMAIL`/`SHOT_PASSWORD`; read-only; captures per-tab screenshots as XCTAttachments (export with `xcrun xcresulttool export attachments`) |
| `HemvoUITests` | `DemoDataSeedUITests` | Env-gated on `SEED_DEMO=1` (+ optional `SEED_PHASES`); **writes real rows** through the app's own add flows — seed a household once, re-running duplicates data |

The gated tests read unprefixed names (`SHOT_EMAIL`, `SHOT_PASSWORD`, `SEED_DEMO`), so they skip on a normal ⌘U pass. Pass them on the `xcodebuild` command line, or as `TEST_RUNNER_`-prefixed **environment variables** (not build settings) when launching from Xcode — the prefix is stripped on the way into the runner.

## Architecture

MVVM with a service layer. The three-layer stack:

1. **Models** (`Hemvo/Core/Models/`) — Plain structs, all `Codable`. No business logic.
2. **ViewModels** (`Hemvo/Core/ViewModels/`) — `@MainActor ObservableObject` classes. Call services, expose `@Published` state to views.
3. **Services** (`Hemvo/Core/Services/`) — Singletons managing persistence, auth, notifications, subscriptions, etc.

Views get ViewModels via `@EnvironmentObject` injected at the root in `Hemvo/App/HemvoApp.swift`. Shared constants live in `Hemvo/Shared/Constants/` (`AppConstants`, `StoreIDs`, `ProfileValidator`).

### Navigation

```
HemvoApp
└─ RootView
    ├─ !isLoggedIn      → OnboardingView (login / signup / password reset)
    ├─ !subscriptionActive → PaywallView
    └─ subscribed       → ContentView (5-tab shell with LiquidTabBar)
         ├─ Dashboard
         ├─ Meals (MealPlannerView → MealHistoryView sheet for past meals, read-only)
         ├─ Budget
         ├─ Schedule
         └─ Maintenance
```

Deep links (`hemvo://reset-password?token=XXX`) are handled in `HemvoApp.onOpenURL` and present `ResetPasswordView` full-screen.

### Data Persistence

- **Supabase (PostgreSQL)** — primary backend for all user, household, and app data. Client configured in `Hemvo/SupabaseClient.swift` with certificate pinning and Keychain session storage. Credentials live in `Hemvo/AppSecrets.swift` (not committed).
- **CoreData** — local structured data via `PersistenceService`, backed by a plain `NSPersistentContainer` (not CloudKit-backed). Kept for offline caching; no iCloud container is configured in either entitlements file.
- **UserDefaults** — ViewModel-level caches (e.g. `hemvo_meals`, `hemvo_events`) and household data (`hemvo_household_v2`). Keys were migrated off the legacy `hb_` prefix by `UserDefaultsMigration.swift`, which also handles compound keys (`hemvo_meals_hh_<code>`, `hemvo_meals_user_<uuid>` — built by `SharedDataKey.make(...)`).
- **UserPreferences** — `@MainActor` singleton that caches four notification toggles in `UserDefaults` and debounce-syncs them to Supabase `profiles` (0.5 s debounce). Avatar color is written to `UserDefaults` only and persisted via `AuthService.updateProfile()`. Seeded from the authoritative profile on login via `seed(from:)`.
- **Keychain** — Supabase auth session token stored via `KeychainHelper` through a custom `KeychainAuthStorage` adapter (see `SupabaseClient.swift`).

### Authentication

Managed by `AuthViewModel` + `AuthService`. All paths ultimately resolve to a Supabase session. Apple/Google social sign-in has been removed.

| Path | Mechanism |
|------|-----------|
| Email/password | `AuthService` → Supabase Auth; `login()` accepts email **or** username (resolves username→email via `get_email_for_username()` SECURITY DEFINER RPC — avoids direct SELECT on `profiles`) |
| Sign up | `AuthService.createAccount()` → `create-account` Edge Function (uses admin API to avoid GoTrue SMTP issues) |
| Biometrics | `LocalAuthentication` (Face ID / Touch ID), enabled after first login |
| Password reset | `send-password-reset-email` Edge Function → deep link `hemvo://reset-password?token=XXX` → `ResetPasswordView` → `reset-user-password` Edge Function (admin API). The client uses `flowType: .implicit` (`SupabaseClient.swift`) so the recovery link's tokens arrive in the URL fragment; a recovery `.signedIn` event must **not** run the normal login pipeline. |
| Change password | `change_user_password` Supabase RPC (SECURITY DEFINER, avoids OTP reauthentication requirement) |

### Subscriptions

StoreKit 2 via `StoreKitService`. Two products (auto-renewable; IDs defined in `Shared/Constants/StoreIDs.swift`):
- `com.hemvo.app.sub.monthly1` — $4.99/mo (the original `...monthly` was deleted in ASC and its ID is permanently reserved by Apple, hence the `1` suffix)
- `com.hemvo.app.sub.annual` — $49.99/yr

**Adding or changing a product ID requires adding it to `KNOWN_PRODUCT_IDS` in `supabase/functions/verify-subscription/index.ts` and redeploying.** The server treats an unknown ID as `active:false`, which the app reads as "Apple says this purchase is invalid" and downgrades the owner to expired.

New users get a 7-day free trial (`AppConstants.trialDurationDays`). This is a **server-side grant, not an Apple introductory offer** — neither product has one, so a trial never auto-converts to a paid subscription. Trials are expired server-side by an hourly `expire_lapsed_trials` job (migration `20260716120000`). After trial, `PaywallView` gates access until a purchase is verified. Subscription status is mirrored to Supabase `profiles.subscription_status` so household members on other devices can read it without StoreKit access; only the `verify-subscription` Edge Function (service-role) may set it to `active`.

### Services Reference

| Service | Location | Responsibility |
|---------|----------|----------------|
| `AuthService` | `Core/Services/` | Supabase Auth: login (email/username), sign-up, profile CRUD, subscription status sync |
| `StoreKitService` | `Core/Services/` | In-app purchases, subscription verification |
| `HouseholdService` | `Features/HouseHold/` | `@MainActor` singleton; manages household state, members, invites, Supabase Realtime subscriptions |
| `PersistenceService` | `Core/Services/` | CoreData stack; use `.preview` for SwiftUI previews |
| `UserPreferences` | `Core/Services/` | UserDefaults cache + Supabase `profiles` debounce-sync for notification prefs; avatar color persisted via `AuthService.updateProfile()` |
| `GroceryViewModel` | `Core/ViewModels/` | Grocery list combining meal-sourced and manual items; syncs to `grocery_items` table with Supabase Realtime; uses `pendingUploadIDs` tombstone set to distinguish unconfirmed local items from remote deletes |
| `PushNotificationService` | `Core/Services/` | Registers APNs tokens to `device_tokens` (upsert keyed on `user_id+device_id` IDFV to prevent duplicate delivery on token rotation); calls `notify-household` Edge Function |
| `NotificationService` | `Core/Services/` | Local push notifications (bills, maintenance, meals, trial expiry); meal notifications are non-repeating (scheduled once per exact calendar date) |
| `HouseholdInviteService` | `Core/Services/` | Invite codes, 7-day expiry, email dispatch |
| `EmailService` | `Core/Services/` | Transactional email via Resend API (API key stored as Supabase secret `RESEND_API_KEY` server-side — not in the app) |
| `PasswordResetService` | `Core/Services/` | Legacy token generation/validation — superseded by Supabase Edge Function flow |
| `CertificatePinner` | `Core/Services/` | SPKI-hash TLS pinning for all Supabase traffic; live leaf expires **2026-09-26** — run `scripts/update-pins.sh` by ~2026-09-05 and add new hashes (keep old for overlap); GitHub Actions workflow monitors expiry |
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
| `reset-user-password` | `ResetPasswordView`, after recovery session | Admin-API password set, bypassing `secure_password_change`; only accepts recovery sessions |
| `verify-subscription` | Purchase / restore | The **only** path allowed to set `profiles.subscription_status = 'active'`; validates the StoreKit transaction against Apple's App Store Server API (bundle ID, product ID allowlist, unrevoked, unexpired) and binds the transaction ID to one profile so it can't be replayed |

### External Integrations

- **Supabase** — auth, PostgreSQL database, Realtime subscriptions, Edge Functions, and APNs push pipeline. Credentials (`supabaseURL`, `supabaseAnonKey`) in `AppSecrets.swift` — do not commit.
- **Resend API** — transactional email (confirmation, password reset, invites). API key is stored as Supabase secret `RESEND_API_KEY` — never reaches the iOS client.
- **Apple Push Notification service (APNs)** — push delivery. Required Supabase secrets: `APNS_KEY_ID` (key VBY93G9JH7), `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`. Debug builds use sandbox; release/TestFlight use production.
- **App Store Connect** — StoreKit product IDs must exist in ASC before purchases work in production.
- **CloudKit** — not currently wired up. No iCloud container is declared in `Hemvo.entitlements` or `HemvoRelease.entitlements` (both only set `aps-environment`), and no Swift code references CloudKit. `PersistenceService` uses a plain `NSPersistentContainer`.
- **GitHub Actions** — `.github/workflows/supabase-keep-alive.yml` pings Supabase on a schedule to prevent the free-tier project from pausing. `.github/workflows/check-cert-pins.yml` monitors certificate pin expiry and opens an issue when rotation is needed.

## Feature Notes

### Budget

- `RecurrenceRule` (`Core/Models/Expense.swift`) supports weekly / **bi-weekly** / monthly / yearly. Bi-weekly is the only rule whose period isn't one unit of its calendar component, so `unitsPerPeriod` (2 for bi-weekly, 1 otherwise) multiplies the stride in `nextOccurrenceDate`. The DB mirrors this via `expenses_recurrence_check` (migration `20260815120000`) — adding a rule client-side without widening that constraint makes the INSERT fail.
- `BudgetSharedComponents.swift` holds the pieces shared by the dashboard, reminders and history sheets: `ScopeBadge` (HOUSEHOLD/PERSONAL), `MoneyText`, `BillMetaPill`, `BillByline`, and `BillPeopleResolver`. Views take a `BillPeopleResolver` rather than reading `HouseholdService` directly.
- Bill Reminders lists **unpaid** bills only (matching `vm.upcomingBills` and the dashboard's Upcoming Bills card); paid bills live in History, reachable from the "All bills paid" state.
- The budget total is `totalCommitted` (not `totalSpent`) — it includes scheduled-but-unpaid bills, so "spent" was misleading.

### Profile & Sign-up Validation

`Hemvo/Shared/Constants/ProfileValidator.swift` is the single client-side rule set for full name (≥3 chars; letters, spaces, hyphens, apostrophes) and username (≥3 chars; alphanumerics and underscores), used by both `LoginView` sign-up and `ProfileView` editing. Enforced server-side too: `create-account` validates at sign-up, and profile edits hit the `validate_profile_name_username` BEFORE UPDATE trigger (migration `20260815140000`). It is deliberately a **trigger, not a CHECK constraint** — two legacy rows violate the rule, and a CHECK would break every future update to them, including `subscription_status` writes from `expire_lapsed_trials` and `verify-subscription`.

## Key Conventions

- All ViewModels are `@MainActor` — do not dispatch to main manually inside them.
- Use `async/await` throughout; avoid callbacks except when wrapping legacy APIs (use `withCheckedContinuation`).
- Feature views live in `Hemvo/Features/<FeatureName>/`. Shared UI components go in `Hemvo/Shared/Components/`.
- `AppConstants.swift` (`Hemvo/Shared/Constants/`) is the single source of truth for magic numbers and external URLs (trial duration, pricing, dashboard row limits, validation minimums, `appStoreID` / `appStoreURL` / `appStoreReviewURL`). App Store links must include the numeric app ID — a bare `apps.apple.com/app/hemvo` 404s.
- `AppSecrets.swift` holds Supabase credentials — it is **not** committed to git. Copy `AppSecrets.swift.example` and fill in values locally (`supabase projects api-keys --project-ref <ref>` retrieves them).
- Supabase calls use the module-level `supabase` constant (defined in `Hemvo/SupabaseClient.swift`) — never create a second client.
- `HouseholdService.shared` is `@MainActor` — always read it from the main actor (use `await MainActor.run { ... }` from background contexts).
- `AuthService` methods that call `supabase.auth.session` are `nonisolated` — calling them from the main actor can cause deadlocks on token refresh.
- SwiftUI previews use `PersistenceService.preview` (in-memory CoreData) and inject mock environment objects.
- Certificate pins in `CertificatePinner.swift`: the live leaf expires **2026-09-26** (verified 2026-07-16 — the pin for it is already shipped and matches the host). Run `scripts/update-pins.sh` by ~2026-09-05, add new SPKI hashes (keep old ones for overlap), ship an app update, then remove stale hashes in a follow-up release once the new cert is live. The 2026-07-29 leaf is the *previous* cert, no longer served — safe to drop from the pin list after 2026-08-12. Verify against the live host rather than trusting this line: `echo | openssl s_client -connect <ref>.supabase.co:443 2>/dev/null | openssl x509 -noout -dates`.
- `PrivacyInfo.xcprivacy` declares UserDefaults (`CA92.1`) required-reason API usage and `NSPrivacyCollectedDataTypeDeviceID` as a collected data type — required for App Store submission. DeviceID is **not** a valid `NSPrivacyAccessedAPIType` category (only UserDefaults, FileTimestamp, SystemBootTime, DiskSpace, ActiveKeyboards are); it only belongs under `NSPrivacyCollectedDataTypes`.
- `Hemvo/App/HemvoApp.swift` includes jailbreak detection; returns `false` in simulator to allow development.
- `Hemvo/Features/Onboarding/EmailValidator.swift` validates disposable email domains (hardcoded blocklist) and MX records via Cloudflare DNS; uses `URLSession.shared` (intentionally unpinned — no credentials sent).
- `profiles` RLS restricts SELECT to own row or household members only (tightened in migration `20260625150000`); `get_email_for_username()` is a SECURITY DEFINER RPC to allow username login without broader profile access.
