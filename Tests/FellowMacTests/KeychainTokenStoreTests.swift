import AidenCore
import XCTest

@testable import FellowMac

@MainActor
final class KeychainTokenStoreTests: XCTestCase {
  private func requireLocalKeychain() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["FELLOW_KEYCHAIN_TESTS"] == "1",
      "Run explicitly on an unlocked local Keychain.")
  }

  func testRoundTripRotationAndLogoutRemoval() async throws {
    try requireLocalKeychain()
    let store = KeychainTokenStore(service: "io.github.hdoria.FellowMac.tests.\(UUID())")
    try await store.clear()
    let empty = try await store.load()
    XCTAssertNil(empty)
    let original = SessionTokens(accessToken: "test-access", refreshToken: "test-refresh")
    let rotated = SessionTokens(accessToken: "test-access-2", refreshToken: "test-refresh-2")
    do {
      try await store.save(original)
      let loaded = try await store.load()
      XCTAssertEqual(loaded, original)
      try await store.save(rotated)
      let updated = try await store.load()
      XCTAssertEqual(updated, rotated)
      try await store.clear()
      let removed = try await store.load()
      XCTAssertNil(removed)
    } catch {
      try? await store.clear()
      throw error
    }
  }

  func testLogoutCannotRemoveAnotherStoresSession() async throws {
    try requireLocalKeychain()
    let service = "io.github.hdoria.FellowMac.tests.\(UUID())"
    let first = KeychainTokenStore(service: service, account: "first")
    let second = KeychainTokenStore(service: service, account: "second")
    let tokens = SessionTokens(accessToken: "test-access", refreshToken: "test-refresh")
    do {
      try await first.save(tokens)
      try await second.save(tokens)
      try await first.clear()
      let remaining = try await second.load()
      XCTAssertEqual(remaining, tokens)
      try await second.clear()
    } catch {
      try? await first.clear()
      try? await second.clear()
      throw error
    }
  }
}
