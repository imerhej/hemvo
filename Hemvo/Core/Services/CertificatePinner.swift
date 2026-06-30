// CertificatePinner.swift
// Hemvo
//
// SPKI (SubjectPublicKeyInfo) certificate pinning for all Supabase traffic.
//
// HOW IT WORKS
// ─────────────────────────────────────────────────────────────────────────
// For every TLS handshake, iOS delivers a URLAuthenticationChallenge with
// the server's full certificate chain. We extract the SubjectPublicKeyInfo
// (SPKI) DER bytes from each certificate, SHA-256 hash them, and compare
// against our set of known-good hashes. If at least one certificate in the
// chain matches, the connection proceeds; otherwise it is cancelled and the
// request fails with NSURLErrorCancelled.
//
// Pinning the SPKI (not the full cert) means we survive cert renewals as
// long as the key pair stays the same. We pin both the leaf and the
// intermediate CA so that either can satisfy the check.
//
// UPDATING PINS
// ─────────────────────────────────────────────────────────────────────────
// Run the helper script `scripts/update-pins.sh` (or the commands below)
// before the current certificate expires (visible in your browser or via
// `openssl s_client`). Add the new hash to pinnedHashes BEFORE removing
// the old one so existing installs keep working during the rollout window.
//
//   LEAF:
//     echo | openssl s_client -servername HOST -connect HOST:443 2>/dev/null \
//       | openssl x509 -pubkey -noout \
//       | grep -v "PUBLIC KEY" | tr -d '\n' | base64 -d \
//       | openssl dgst -sha256 -binary | base64
//
//   INTERMEDIATE (cert #2 in chain):
//     echo | openssl s_client -servername HOST -connect HOST:443 -showcerts 2>/dev/null \
//       | awk '/-----BEGIN CERTIFICATE-----/{i++} i==2{print} /-----END CERTIFICATE-----/ && i==2{exit}' \
//       | openssl x509 -pubkey -noout \
//       | grep -v "PUBLIC KEY" | tr -d '\n' | base64 -d \
//       | openssl dgst -sha256 -binary | base64
// ─────────────────────────────────────────────────────────────────────────

internal import Foundation
internal import Security
internal import CryptoKit

// MARK: - CertificatePinner

/// URLSessionDelegate that enforces SPKI-hash certificate pinning.
/// Pass an instance of this as the delegate when creating the URLSession
/// used by SupabaseClient (see SupabaseClient.swift).
final class CertificatePinner: NSObject, URLSessionDelegate {

    // MARK: - Pinned hashes
    // SHA-256 of the SubjectPublicKeyInfo DER bytes, base64-encoded.
    // Managed by .github/workflows/check-cert-pins.yml (runs every Monday).
    // Last checked: 2026-06-30
    // New hashes are added alongside old ones (parallel pinning); hashes whose
    // expiry date is >14 days past are pruned automatically on the next run.
    private static let pinnedHashes: Set<String> = [
        "ZcJbApTb7wyllleAjHw2vYAskqdT+DhMY9aPDFwAtf4=",  // leaf (expires 2026-09-26, remove after 2026-07-21)
        "p51goejPCgGH+Oog/MU2k6PObcEfTrrr73jUcuWJ7w0=",  // leaf (expires 2026-07-29, remove after 2026-08-12)
        "kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4="   // Google Trust Services WE1 intermediate CA
    ]

    // MARK: - URLSessionDelegate

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle server-trust challenges; fall through for everything else.
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Standard OS validation first (revocation, expiry, hostname).
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Walk the chain looking for a pinned hash.
        // SecTrustCopyCertificateChain replaces the deprecated SecTrustGetCertificateAtIndex (iOS 15+).
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        for cert in chain {
            if let spkiHash = spkiSHA256(of: cert), CertificatePinner.pinnedHashes.contains(spkiHash) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // No pinned certificate found — reject.
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - SPKI extraction

    /// Returns the base64-encoded SHA-256 hash of the SubjectPublicKeyInfo
    /// DER bytes for `certificate`, or nil if extraction fails.
    private func spkiSHA256(of certificate: SecCertificate) -> String? {
        // Extract the public key from the certificate.
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }

        // Serialise the public key to DER (PKCS#8 / SubjectPublicKeyInfo).
        var error: Unmanaged<CFError>?
        guard let spkiData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { return nil }

        // SecKeyCopyExternalRepresentation for RSA gives us raw PKCS#1 DER;
        // for EC it gives us the uncompressed point. Neither includes the
        // algorithm-identifier prefix that SPKI requires, so we prepend the
        // correct ASN.1 header based on key type and size before hashing.
        guard let spkiDER = addSPKIHeader(to: spkiData, key: publicKey) else { return nil }

        // SHA-256 and base64-encode using CryptoKit (replaces deprecated CC_SHA256).
        let hash = SHA256.hash(data: spkiDER)
        return Data(hash).base64EncodedString()
    }

    // MARK: - ASN.1 SPKI header prefixes

    // Hard-coded DER TLV headers for the most common public key types.
    // These are the AlgorithmIdentifier + BIT STRING wrapper bytes that
    // precede the raw key material in a SubjectPublicKeyInfo structure.
    // Regenerate with: openssl asn1parse -in <(openssl ec -pubout ...) -inform PEM

    private static let ecP256Header: [UInt8] = [
        0x30, 0x59,                                     // SEQUENCE (89 bytes)
        0x30, 0x13,                                     //   SEQUENCE (19 bytes)  — AlgorithmIdentifier
        0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,  //     OID ecPublicKey
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, //     OID prime256v1
        0x03, 0x42, 0x00                                //   BIT STRING (66 bytes, 0 padding)
    ]

    private static let ecP384Header: [UInt8] = [
        0x30, 0x76,
        0x30, 0x10,
        0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22,
        0x03, 0x62, 0x00
    ]

    private static let rsa2048Header: [UInt8] = [
        0x30, 0x82, 0x01, 0x22,                         // SEQUENCE (290 bytes)
        0x30, 0x0d,                                     //   SEQUENCE (13 bytes)
        0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, // OID rsaEncryption
        0x05, 0x00,                                     //   NULL
        0x03, 0x82, 0x01, 0x0f, 0x00                    //   BIT STRING (271 bytes, 0 padding)
    ]

    private static let rsa4096Header: [UInt8] = [
        0x30, 0x82, 0x02, 0x22,
        0x30, 0x0d,
        0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
        0x05, 0x00,
        0x03, 0x82, 0x02, 0x0f, 0x00
    ]

    /// Prepends the correct SPKI AlgorithmIdentifier header so we get the
    /// same byte sequence that `openssl x509 -pubkey` would produce.
    private func addSPKIHeader(to keyData: Data, key: SecKey) -> Data? {
        guard let attrs = SecKeyCopyAttributes(key) as? [String: Any],
              let keyType  = attrs[kSecAttrKeyType  as String] as? String,
              let keySize  = attrs[kSecAttrKeySizeInBits as String] as? Int
        else { return nil }

        let ecType  = kSecAttrKeyTypeEC  as String
        let rsaType = kSecAttrKeyTypeRSA as String

        let header: [UInt8]
        switch (keyType, keySize) {
        case (ecType,  256):  header = CertificatePinner.ecP256Header
        case (ecType,  384):  header = CertificatePinner.ecP384Header
        case (rsaType, 2048): header = CertificatePinner.rsa2048Header
        case (rsaType, 4096): header = CertificatePinner.rsa4096Header
        default:
            // Unknown key type — skip; the connection will be rejected.
            return nil
        }

        return Data(header) + keyData
    }
}

