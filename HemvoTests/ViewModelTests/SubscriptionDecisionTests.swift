//
//  SubscriptionDecisionTests.swift
//  HemvoTests
//
//  Pure-logic coverage for the subscription reconciliation decisions in
//  AuthViewModel. These are the branches that decide whether an owner's
//  Supabase `subscription_status` row gets flipped — which in turn drives
//  whether household members keep seeing the "ask the owner to renew" popup.
//
//  The functions under test are pure (no StoreKit / network / Keychain), so
//  they can be exercised directly without spinning up the full ViewModel.
//

import Testing
import Foundation
@testable import Hemvo

struct SubscriptionDecisionTests {

    // MARK: - followUp(for:) — the tri-state Apple-verification mapping
    //
    // This is the fix for the reported bug: a transient verification failure
    // (`.unverifiable`) must NOT expire the owner, or every household member is
    // stranded on the grace popup until they're locked out.

    @Test func activeVerificationConfirmsSubscription() {
        #expect(SubscriptionDecision.followUp(for: .active) == .confirmed)
    }

    @Test func invalidVerificationDowngrades() {
        #expect(SubscriptionDecision.followUp(for: .invalid) == .downgrade)
    }

    @Test func unverifiableLeavesRowUnchanged() {
        // The regression guard: a network/edge-function blip is NOT a downgrade.
        #expect(SubscriptionDecision.followUp(for: .unverifiable) == .leaveUnchanged)
    }

    // MARK: - ownerServerSync(...) — what to do given local entitlement + trial

    @Test func entitledWithTransactionVerifiesIt() {
        let result = SubscriptionDecision.ownerServerSync(
            hasSub: true, transactionID: 42, isTrialActive: false)
        #expect(result == .verifyTransaction(42))
    }

    @Test func entitledWithoutTransactionLeavesRowUnchanged() {
        // Simulator dev bypass: hasSub == true but no transaction id. Must not
        // expire the row (that would start members' grace clock spuriously).
        let result = SubscriptionDecision.ownerServerSync(
            hasSub: true, transactionID: nil, isTrialActive: false)
        #expect(result == .leaveUnchanged)
    }

    @Test func noEntitlementWithLiveTrialActivatesTrial() {
        let result = SubscriptionDecision.ownerServerSync(
            hasSub: false, transactionID: nil, isTrialActive: true)
        #expect(result == .activateTrial)
    }

    @Test func noEntitlementNoTrialExpires() {
        let result = SubscriptionDecision.ownerServerSync(
            hasSub: false, transactionID: nil, isTrialActive: false)
        #expect(result == .expire)
    }

    @Test func entitlementTakesPrecedenceOverExpiredTrial() {
        // A live entitlement wins even if the trial flag is false: we verify,
        // never expire.
        let result = SubscriptionDecision.ownerServerSync(
            hasSub: true, transactionID: 7, isTrialActive: false)
        #expect(result == .verifyTransaction(7))
    }

    // MARK: - graceDaysRemaining(since:) — the member-side shared countdown
    //
    // Every member device derives the same days-left from the owner's single
    // server-stamped lapse timestamp. When it hits 0 the popup stops and the
    // member is routed to OwnerLapsedView instead.

    @MainActor
    @Test func graceStartsAtFullWindowWhenJustLapsed() {
        #expect(AuthViewModel.graceDaysRemaining(since: Date())
                == AppConstants.gracePeriodDays)
    }

    @MainActor
    @Test func graceDecrementsMidWindow() {
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86_400 - 100)
        #expect(AuthViewModel.graceDaysRemaining(since: twoDaysAgo)
                == AppConstants.gracePeriodDays - 2)
    }

    @MainActor
    @Test func graceClampsToZeroPastWindow() {
        let pastWindow = Date().addingTimeInterval(
            -Double(AppConstants.gracePeriodDays) * 86_400 - 3_600)
        #expect(AuthViewModel.graceDaysRemaining(since: pastWindow) == 0)
    }
}
