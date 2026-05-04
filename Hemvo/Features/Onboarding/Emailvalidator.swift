// EmailValidator.swift
// Hemvo
//
// Four-layer email sanitisation:
//   1. RFC 5322 format check (regex)
//   2. Disposable / throwaway domain blocklist
//   3. Common domain typo suggestions (gmial.com → gmail.com)
//   4. Async MX record lookup via Cloudflare DNS-over-HTTPS
//
// Duplicate email check now uses Supabase Auth instead of loadAllUsers().

internal import Foundation
internal import Combine
internal import SwiftUI
internal import Supabase

// MARK: - ValidationResult

enum EmailValidationResult: Equatable {
    case valid
    case invalid(String)
    case suggestion(String)
    case checking
    case alreadyRegistered(String)
}

// MARK: - EmailValidator

@MainActor
final class EmailValidator: ObservableObject {

    static let shared = EmailValidator()
    private init() {}

    @Published var result: EmailValidationResult = .valid

    private var mxTask: Task<Void, Never>? = nil

    // MARK: - Entry point
    func validate(_ raw: String, isSignUp: Bool = false) {
        mxTask?.cancel()
        mxTask = nil

        let email = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !email.isEmpty else { result = .valid; return }

        // 1. Format check
        guard isValidFormat(email) else {
            result = .invalid("Enter a valid email address.")
            return
        }

        let domain = email.components(separatedBy: "@").last ?? ""

        // 2. Disposable domain check
        if Self.disposableDomains.contains(domain) {
            result = .invalid("Disposable email addresses are not allowed.")
            return
        }

        // 3. Typo suggestion
        if let fix = Self.typoMap[domain] {
            result = .suggestion(
                "Did you mean \(email.replacingOccurrences(of: domain, with: fix))?")
            return
        }

        // 4. Duplicate check via Supabase (sign-up only) + MX lookup
        result = .checking
        mxTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }

            // Duplicate check — attempt a password reset; if Supabase returns
            // no error the email exists. We catch and treat errors as "not found".
            if isSignUp {
                let exists = await emailExistsInSupabase(email)
                guard !Task.isCancelled else { return }
                if exists {
                    result = .alreadyRegistered(email)
                    return
                }
            }

            // MX record lookup
            let hasMX = await lookupMX(domain: domain)
            guard !Task.isCancelled else { return }
            result = hasMX
                ? .valid
                : .invalid(
                    "This domain doesn't appear to accept email. Check for typos.")
        }
    }

    // MARK: - Quick synchronous check (no network)
    func quickCheck(_ raw: String) -> EmailValidationResult {
        let email = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !email.isEmpty   else { return .invalid("Email address is required.") }
        guard isValidFormat(email) else { return .invalid("Enter a valid email address.") }
        let domain = email.components(separatedBy: "@").last ?? ""
        if Self.disposableDomains.contains(domain) {
            return .invalid("Disposable email addresses are not allowed.")
        }
        if let fix = Self.typoMap[domain] {
            let suggestion = email.replacingOccurrences(of: domain, with: fix)
            return .suggestion("Did you mean \(suggestion)?")
        }
        return .valid
    }

    func reset() { mxTask?.cancel(); result = .valid }

    // MARK: - Supabase duplicate check
    // We attempt to sign up with a deliberately bad password.
    // Supabase returns "User already registered" if the email exists.
    private func emailExistsInSupabase(_ email: String) async -> Bool {
        do {
            // Use OTP sign-in check — doesn't create an account, just probes
            try await supabase.auth.signInWithOTP(email: email, shouldCreateUser: false)
            // If it succeeds without error, the account exists
            return true
        } catch let error as AuthError {
            // "Email not confirmed" or similar → account exists
            let msg = error.localizedDescription.lowercased()
            if msg.contains("already registered") || msg.contains("email not confirmed") {
                return true
            }
            return false
        } catch {
            // Any other error — treat as not found to avoid blocking sign-up
            return false
        }
    }

    // MARK: - RFC 5322 format check
    private func isValidFormat(_ email: String) -> Bool {
        let pattern = #"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(email.startIndex..., in: email)
        guard regex.firstMatch(in: email, range: range) != nil else { return false }
        let local = email.components(separatedBy: "@").first ?? ""
        if local.hasPrefix(".") || local.hasSuffix(".")  { return false }
        if local.contains("..")                           { return false }
        if local.count > 64                              { return false }
        if email.count > 254                             { return false }
        return true
    }

    // MARK: - Disposable domain blocklist
    private static let disposableDomains: Set<String> = [
        "mailinator.com", "mailinator.net", "mailinater.com", "mailinator2.com",
        "maildrop.cc", "trashmail.com", "trashmail.net", "trashmail.me",
        "trashmail.at", "trashmail.io", "trashmail.org",
        "guerrillamail.com", "guerrillamail.net", "guerrillamail.org",
        "guerrillamail.biz", "guerrillamail.de", "guerrillamail.info",
        "grr.la", "guerrillamailblock.com", "spam4.me",
        "tempmail.com", "tempmail.net", "tempmail.org", "temp-mail.org",
        "temp-mail.io", "10minutemail.com", "10minutemail.net",
        "10minutemail.org", "10minemail.com",
        "20minutemail.com", "throwam.com",
        "yopmail.com", "yopmail.fr", "yopmail.net",
        "cool.fr.nf", "jetable.fr.nf", "nospam.ze.tc",
        "sharklasers.com", "spam4.me",
        "fakeinbox.com", "fakemail.fr", "spamgourmet.com",
        "spamgourmet.net", "spamgourmet.org",
        "dodgeit.com", "spammotel.com", "spam.la",
        "getairmail.com", "filzmail.com", "dispostable.com",
        "spamfree24.org", "spaml.de",
        "mt2009.com", "mt2014.com", "mailoo.org",
        "spamthisplease.com", "binkmail.com", "bobmail.info",
        "chammy.info", "devnullmail.com", "letthemeatspam.com",
        "lol.ovpn.to", "mailnull.com", "spamgob.com",
        "trashdevil.com", "trashdevil.de", "uggsrock.com",
        "venompen.com", "wuzupmail.net", "xoxy.net",
        "yep.it", "yuurok.com", "zehnminutenmail.de",
        "discard.email", "discardmail.com", "discardmail.de",
        "suremail.info", "spamfloz.com",
        "nada.email", "nada.ltd",
        "mailnesia.com", "zetmail.com", "emkei.cz",
        "pookmail.com", "spamhole.com", "jetable.com",
        "mailexpire.com", "mail-filter.com",
        "inoutmail.de", "inoutmail.eu", "inoutmail.info", "inoutmail.net",
        "spamfree24.de", "spamfree24.eu", "spamfree24.info",
        "spamfree24.net", "spam.su",
    ]

    // MARK: - Typo map
    private static let typoMap: [String: String] = [
        "gmial.com":     "gmail.com",
        "gmal.com":      "gmail.com",
        "gmaill.com":    "gmail.com",
        "gmali.com":     "gmail.com",
        "gnail.com":     "gmail.com",
        "gmail.co":      "gmail.com",
        "gmail.org":     "gmail.com",
        "gmail.net":     "gmail.com",
        "gamil.com":     "gmail.com",
        "gmai.com":      "gmail.com",
        "gmailcom":      "gmail.com",
        "yahooo.com":    "yahoo.com",
        "yaho.com":      "yahoo.com",
        "yhoo.com":      "yahoo.com",
        "yahoo.co":      "yahoo.com",
        "yahoo.org":     "yahoo.com",
        "yhaoo.com":     "yahoo.com",
        "yaoo.com":      "yahoo.com",
        "outlok.com":    "outlook.com",
        "outllok.com":   "outlook.com",
        "outlookk.com":  "outlook.com",
        "outlock.com":   "outlook.com",
        "hotmial.com":   "hotmail.com",
        "hotmil.com":    "hotmail.com",
        "hotmail.co":    "hotmail.com",
        "hotmaill.com":  "hotmail.com",
        "iclod.com":     "icloud.com",
        "icoud.com":     "icloud.com",
        "iclould.com":   "icloud.com",
        "appel.com":     "apple.com",
        "protonmai.com": "protonmail.com",
        "protonmal.com": "protonmail.com",
        "mocrosoft.com": "microsoft.com",
    ]

    // MARK: - MX record lookup
    private func lookupMX(domain: String) async -> Bool {
        for base in [
            "https://cloudflare-dns.com/dns-query",
            "https://dns.google/resolve"
        ] {
            if let result = await queryMX(base: base, domain: domain) { return result }
        }
        return true // Fail open — don't block user if DNS is unreachable
    }

    private func queryMX(base: String, domain: String) async -> Bool? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "name", value: domain),
            URLQueryItem(name: "type", value: "MX")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 5
        )
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else { return nil }
            let status  = json["Status"] as? Int ?? -1
            let answers = json["Answer"] as? [[String: Any]] ?? []
            return status == 0 && !answers.isEmpty
        } catch {
            return nil
        }
    }
}
