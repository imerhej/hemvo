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
    supabaseURL: URL(string: AppSecrets.supabaseURL) ?? { fatalError("AppSecrets.supabaseURL is not a valid URL") }(),
    supabaseKey: AppSecrets.supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            storage: KeychainAuthStorage(),
            emitLocalSessionAsInitialSession: true
        ),
        global: SupabaseClientOptions.GlobalOptions(
            session: pinnedSession
        )
    )
)
