import AidenCore
import Foundation
import Security

actor KeychainTokenStore: TokenStore {
  private let service: String
  private let account: String

  init(service: String = "io.github.hdoria.FellowMac.session", account: String = "fellow-session") {
    self.service = service
    self.account = account
  }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
  }

  func load() async throws -> SessionTokens? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data,
      let tokens = try? JSONDecoder().decode(SessionTokens.self, from: data),
      !tokens.accessToken.isEmpty, !tokens.refreshToken.isEmpty
    else {
      throw AidenError.storage
    }
    return tokens
  }

  func save(_ tokens: SessionTokens) async throws {
    guard !tokens.accessToken.isEmpty, !tokens.refreshToken.isEmpty,
      let data = try? JSONEncoder().encode(tokens)
    else { throw AidenError.storage }
    let changes = [kSecValueData as String: data]
    let updated = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else { throw AidenError.storage }
    var item = query
    item[kSecValueData as String] = data
    item[kSecAttrLabel as String] = "Fellow Mac session"
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
      throw AidenError.storage
    }
  }

  func clear() async throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AidenError.storage
    }
  }
}
