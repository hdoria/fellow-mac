import Foundation

/// Owns authentication independently of the UI; every await rechecks the account generation.
actor AidenSession {
  static let baseURL = URL(string: "https://l8qtmnc692.execute-api.us-west-2.amazonaws.com/v2")!
  private let store: any TokenStore
  private let transport: any HTTPTransport
  private var tokens: SessionTokens?
  private var generation: UInt64 = 0
  private var refreshTask: Task<SessionTokens, Error>?
  private var persistenceTask: Task<Void, Error>?
  private var retryAfter: Date?

  init(store: any TokenStore, transport: any HTTPTransport) {
    self.store = store
    self.transport = transport
  }

  func restore() async throws -> Bool {
    let expected = generation
    do {
      let restored = try await store.load()
      guard expected == generation else { throw AidenError.sessionChanged }
      guard let restored else { return false }
      guard !restored.accessToken.isEmpty, !restored.refreshToken.isEmpty else {
        throw AidenError.authentication
      }
      tokens = restored
      return true
    } catch let error as AidenError { throw error } catch { throw AidenError.storage }
  }

  func login(email: String, password: String, timezone: String) async throws {
    guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty,
      TimeZone(identifier: timezone) != nil
    else { throw AidenError.authentication }
    generation &+= 1
    let expected = generation
    tokens = nil
    refreshTask?.cancel()
    refreshTask = nil
    try await persist(nil)
    guard expected == generation else { throw AidenError.sessionChanged }
    let body = try JSONEncoder().encode([
      "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      "password": password, "timezone": timezone,
    ])
    let response = try await send(
      path: "auth/login", method: "POST", body: body, token: nil, mutation: false)
    guard expected == generation else { throw AidenError.sessionChanged }
    try check(response, mutation: false)
    let parsed = try decodeTokens(response.data, previous: nil)
    try await persist(parsed)
    guard expected == generation else { throw AidenError.sessionChanged }
    tokens = parsed
  }

  func logout() async throws {
    generation &+= 1
    tokens = nil
    retryAfter = nil
    refreshTask?.cancel()
    refreshTask = nil
    try await persist(nil)
  }

  /// Calls made by earlier accounts must not regain authorization after logout.
  func currentGeneration() -> UInt64 { generation }

  func request(
    path: String, method: String = "GET", body: Data? = nil, acceptedStatuses: Set<Int> = [],
    expectedGeneration: UInt64? = nil
  ) async throws -> HTTPResponse {
    if let expectedGeneration, expectedGeneration != generation { throw AidenError.sessionChanged }
    guard let initial = tokens else { throw AidenError.authentication }
    let expected = generation
    let mutation = method != "GET"
    let first = try await send(
      path: path, method: method, body: body, token: initial.accessToken, mutation: mutation)
    guard expected == generation else { throw AidenError.sessionChanged }
    if first.status == 401 && !mutation {
      // Another overlapping read may already have renewed the same session.
      if tokens?.accessToken == initial.accessToken { try await refresh(expected: expected) }
      guard expected == generation, let renewed = tokens else { throw AidenError.sessionChanged }
      let second = try await send(
        path: path, method: method, body: body, token: renewed.accessToken, mutation: false)
      guard expected == generation else { throw AidenError.sessionChanged }
      if second.status == 401 { try await invalidate(expected: expected) }
      if !acceptedStatuses.contains(second.status) { try check(second, mutation: false) }
      return second
    }
    if !acceptedStatuses.contains(first.status) { try check(first, mutation: mutation) }
    return first
  }

  private func refresh(expected: UInt64) async throws {
    guard let existing = tokens else { throw AidenError.authentication }
    let task: Task<SessionTokens, Error>
    if let pending = refreshTask {
      task = pending
    } else {
      let transport = transport
      task = Task {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("auth/refresh-token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refreshToken": existing.refreshToken])
        let response: HTTPResponse
        do { response = try await transport.send(request) } catch { throw AidenError.unavailable }
        guard response.status != 401 && response.status != 403 else {
          throw AidenError.authentication
        }
        guard (200..<300).contains(response.status) else {
          if response.status == 429 {
            throw AidenError.rateLimited(seconds: Self.retrySeconds(response))
          }
          throw AidenError.unavailable
        }
        return try Self.tokensFrom(response.data, previous: existing)
      }
      refreshTask = task
    }
    do {
      let renewed = try await task.value
      guard expected == generation else { throw AidenError.sessionChanged }
      if tokens?.accessToken == existing.accessToken {
        // Set memory before awaiting persistence so other waiters cannot rotate twice.
        tokens = renewed
        try await persist(renewed)
        guard expected == generation else { throw AidenError.sessionChanged }
      }
      refreshTask = nil
    } catch {
      guard expected == generation else { throw AidenError.sessionChanged }
      refreshTask = nil
      if error as? AidenError == .authentication { try await invalidate(expected: expected) }
      if case .rateLimited(let seconds) = error as? AidenError {
        retryAfter = Date().addingTimeInterval(Double(seconds))
      }
      throw error
    }
  }

  private func invalidate(expected: UInt64) async throws {
    guard expected == generation else { throw AidenError.sessionChanged }
    generation &+= 1
    refreshTask?.cancel()
    refreshTask = nil
    tokens = nil
    try await persist(nil)
  }

  /// Orders save/clear even for an asynchronous TokenStore that suspends midway through a save.
  private func persist(_ value: SessionTokens?) async throws {
    let previous = persistenceTask
    let store = store
    let operation = Task {
      _ = try? await previous?.value
      if let value { try await store.save(value) } else { try await store.clear() }
    }
    persistenceTask = operation
    do { try await operation.value } catch {
      tokens = nil
      throw AidenError.storage
    }
  }

  private func send(path: String, method: String, body: Data?, token: String?, mutation: Bool)
    async throws -> HTTPResponse
  {
    if let retryAfter, retryAfter > Date() {
      throw AidenError.rateLimited(seconds: max(1, Int(ceil(retryAfter.timeIntervalSinceNow))))
    }
    guard let url = URL(string: Self.baseURL.absoluteString + "/" + path), url.scheme == "https",
      url.host == Self.baseURL.host
    else { throw AidenError.invalidResponse }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    do {
      let response = try await transport.send(request)
      guard response.data.count <= 2_000_000 else { throw AidenError.invalidResponse }
      return response
    } catch is CancellationError { throw CancellationError() } catch let error as AidenError {
      throw error
    } catch { throw mutation ? AidenError.uncertainResult : AidenError.unavailable }
  }

  private func check(_ response: HTTPResponse, mutation: Bool) throws {
    if (200..<300).contains(response.status) { return }
    if response.status == 401 || response.status == 403 { throw AidenError.authentication }
    if response.status == 429 {
      let seconds = Self.retrySeconds(response)
      retryAfter = Date().addingTimeInterval(Double(seconds))
      throw AidenError.rateLimited(seconds: seconds)
    }
    if mutation && (response.status == 408 || response.status >= 500) {
      throw AidenError.uncertainResult
    }
    throw AidenError.unavailable
  }

  private func decodeTokens(_ data: Data, previous: SessionTokens?) throws -> SessionTokens {
    try Self.tokensFrom(data, previous: previous)
  }
  private static func tokensFrom(_ data: Data, previous: SessionTokens?) throws -> SessionTokens {
    struct Payload: Decodable {
      let accessToken: String
      let refreshToken: String?
    }
    guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
      !payload.accessToken.isEmpty,
      let refresh = payload.refreshToken ?? previous?.refreshToken, !refresh.isEmpty
    else { throw AidenError.invalidResponse }
    return SessionTokens(accessToken: payload.accessToken, refreshToken: refresh)
  }
  private static func retrySeconds(_ response: HTTPResponse) -> Int {
    guard let value = response.headers.first(where: { $0.key.lowercased() == "retry-after" })?.value
    else { return 60 }
    if let seconds = Int(value), seconds >= 0 { return min(seconds, 86400) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
    return formatter.date(from: value).map {
      max(1, min(86400, Int(ceil($0.timeIntervalSinceNow))))
    } ?? 60
  }
}
