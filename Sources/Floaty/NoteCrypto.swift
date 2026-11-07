import CryptoKit
import Foundation
import Security

/// 잠긴 메모의 본문 파일을 암호화한다. 키는 로그인 키체인에 두고, 메모 파일만 복사되거나 백업에서 꺼내져도 읽을 수 없게 한다.
///
/// 키체인 항목은 모든 앱이 묻지 않고 읽을 수 있게 만든다. 무료(임시) 서명은 빌드할 때마다 서명이 바뀌어,
/// 이 앱만 허용하면 업데이트할 때마다 키체인 암호를 묻기 때문이다. 그래서 이 Mac에서 내 계정으로 도는 다른 앱까지 막지는 못한다.
enum NoteCrypto {
    static let service = "com.eddieee.Floaty"
    /// 시험할 때 넣으면 키체인을 쓰지 않고 이 키를 쓴다.
    static var testKey: SymmetricKey?
    static let account = "locked-notes-key"
    private static let magic = Data("FLTYENC1".utf8)

    enum Failure: Error {
        case noKey, keychain(OSStatus), malformed
    }

    static func isEncrypted(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    static func encrypt(_ plain: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plain, using: try key(createIfMissing: true))
        guard let combined = sealed.combined else { throw Failure.malformed }
        return magic + combined
    }

    static func decrypt(_ data: Data) throws -> Data {
        guard isEncrypted(data) else { throw Failure.malformed }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
        return try AES.GCM.open(box, using: try key(createIfMissing: false))
    }

    private static var cached: SymmetricKey?

    private static func key(createIfMissing: Bool) throws -> SymmetricKey {
        if let testKey { return testKey }
        if let cached { return cached }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            let key = SymmetricKey(data: data)
            cached = key
            return key
        }
        guard status == errSecItemNotFound else { throw Failure.keychain(status) }
        guard createIfMissing else { throw Failure.noKey }

        let key = SymmetricKey(size: .bits256)
        query.removeValue(forKey: kSecReturnData as String)
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        query[kSecAttrLabel as String] = "Floaty locked notes"
        if let access = allApplicationsAccess() { query[kSecAttrAccess as String] = access }
        let added = SecItemAdd(query as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.keychain(added) }
        cached = key
        return key
    }

    /// 신뢰할 앱 목록을 비우지 않고 nil로 주면 모든 앱이 확인 없이 읽는다.
    private static func allApplicationsAccess() -> SecAccess? {
        var access: SecAccess?
        let status = SecAccessCreate("Floaty locked notes" as CFString, nil, &access)
        return status == errSecSuccess ? access : nil
    }

}
