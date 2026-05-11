import Vapor
import Crypto

// MARK: - Encryption Service
// Per INTEGRATION_SPECS.md Section 1.2 — AES-256-GCM encryption for token storage.
// Key derived from WHOOP_TOKEN_ENCRYPTION_KEY via HKDF-SHA256.

struct EncryptionService {

    /// Encrypt a plaintext string using AES-256-GCM.
    /// Storage format: base64(nonce || ciphertext || tag) as a single string.
    static func encrypt(_ plaintext: String) throws -> String {
        let key = try deriveKey()
        let nonce = AES.GCM.Nonce()
        let data = Data(plaintext.utf8)
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        guard let combined = sealedBox.combined else {
            throw Abort(.internalServerError, reason: "Encryption failed.")
        }
        return combined.base64EncodedString()
    }

    /// Decrypt a base64-encoded AES-256-GCM ciphertext.
    static func decrypt(_ ciphertext: String) throws -> String {
        let key = try deriveKey()
        guard let combined = Data(base64Encoded: ciphertext) else {
            throw Abort(.internalServerError, reason: "Invalid ciphertext encoding.")
        }
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        guard let result = String(data: decryptedData, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Decryption produced invalid UTF-8.")
        }
        return result
    }

    /// Derive AES-256 key from environment variable using HKDF-SHA256.
    /// Salt: "whoop-token-v1", Info: "tempo-whoop-encryption"
    private static func deriveKey() throws -> SymmetricKey {
        guard let envKey = Environment.get("WHOOP_TOKEN_ENCRYPTION_KEY") else {
            throw Abort(.internalServerError, reason: "WHOOP_TOKEN_ENCRYPTION_KEY not set.")
        }
        let inputKey = SymmetricKey(data: Data(envKey.utf8))
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: Data("whoop-token-v1".utf8),
            info: Data("tempo-whoop-encryption".utf8),
            outputByteCount: 32
        )
        return derivedKey
    }

}
