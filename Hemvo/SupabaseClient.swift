//
//  SupabaseClient.swift
//  Hemvo
//
//  Created by Issam Merhej on 4/25/26.
//

internal import Foundation
internal import Supabase
internal import Auth

// Routes Supabase session storage through KeychainHelper so that
// KeychainHelper.shared.deleteAll() on account deletion wipes the
// Supabase session token along with all other app Keychain items.
//
// SECURITY TRADEOFF (deliberate, not an oversight): this token is stored
// with the default iCloudSync-eligible accessibility (kSecAttrAccessibleWhenUnlocked,
// see KeychainHelper.save) so a reinstall on the same or a new device can
// silently restore the session. That accessibility class is incompatible
// with SecAccessControl(.biometryCurrentSet), so Face ID/Touch ID in
// AuthViewModel.loginWithBiometrics() only gates the app's own UI flow —
// it does not add a biometric requirement to read this Keychain item
// directly (e.g. via jailbreak or backup extraction). We accept this:
// the item is a revocable refresh token, not a password, and jailbroken/
// extracted devices are already treated as a separate risk category
// (see jailbreak detection in HemvoApp.swift). If this ever needs to
// change, biometric-locking this item requires giving up the cross-device
// iCloud restore behavior (kSecAttrAccessibleWhenUnlockedThisDeviceOnly only).
private struct KeychainAuthStorage: AuthLocalStorage {
    private let key = "supabase.auth.token"

    func store(key: String, value: Data) throws {
        KeychainHelper.shared.save(value, key: key)
    }

    func retrieve(key: String) throws -> Data? {
        KeychainHelper.shared.load(key: key)
    }

    func remove(key: String) throws {
        KeychainHelper.shared.delete(key: key)
    }
}

// MARK: - Certificate-pinned URLSession
// CertificatePinner validates every TLS handshake against our known-good
// SPKI hashes (see CertificatePinner.swift). All Supabase requests — auth,
// PostgREST, Storage, and Edge Functions — go through this session.
private let _pinner = CertificatePinner()
private let pinnedSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest  = 30
    config.timeoutIntervalForResource = 60
    // Use a serial OperationQueue so the delegate is always called on the
    // same thread, matching URLSession.shared's default behaviour.
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.name = "com.hemvo.app.supabase-pinned-session"
    return URLSession(configuration: config, delegate: _pinner, delegateQueue: queue)
}()

// MARK: - Supabase client
let supabase = SupabaseClient(
    supabaseURL: AppSecrets.supabaseBaseURL,
    supabaseKey: AppSecrets.supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            storage: KeychainAuthStorage(),
            // .implicit, not the SDK-default .pkce: the password-reset link is
            // generated server-side (send-password-reset-email Edge Function via
            // admin.generateLink), so GoTrue's /verify redirect returns the
            // session as URL-fragment tokens with no ?code= param. Under .pkce,
            // auth.session(from:) rejects that URL ("Not a valid PKCE flow URL")
            // and the reset deep link dies silently. Implicit-flow parsing still
            // validates the token server-side (GET /user) before establishing
            // the session. No other flow here depends on PKCE (no OAuth/OTP).
            flowType: .implicit,
            emitLocalSessionAsInitialSession: true
        ),
        global: SupabaseClientOptions.GlobalOptions(
            session: pinnedSession
        )
    )
)
