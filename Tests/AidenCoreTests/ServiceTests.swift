import Foundation
import Testing

@testable import AidenCore

actor MemoryTokens: TokenStore {
  var value: SessionTokens?
  var saved: [SessionTokens] = []
  init(_ value: SessionTokens? = nil) { self.value = value }
  func load() -> SessionTokens? { value }
  func save(_ tokens: SessionTokens) {
    value = tokens
    saved.append(tokens)
  }
  func clear() { value = nil }
}

actor ScriptedTransport: HTTPTransport {
  typealias Handler = @Sendable (URLRequest) async throws -> HTTPResponse
  let handler: Handler
  var requests: [URLRequest] = []
  init(_ handler: @escaping Handler) { self.handler = handler }
  func send(_ request: URLRequest) async throws -> HTTPResponse {
    requests.append(request)
    return try await handler(request)
  }
}

func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
  HTTPResponse(status: status, headers: headers, data: Data(text.utf8))
}
let testTokens = SessionTokens(accessToken: "synthetic-access", refreshToken: "synthetic-refresh")
let safeDeviceJSON =
  #"{"id":"a1","firmwareVersion":"1.5.16","timezone":"America/Maceio","isConnected":true,"state":null,"missingWater":false,"lidClosed":true,"singleBrewBasketPresent":true,"cleaning":false,"rinsing":false}"#

@Test func loginLowercasesEmailAndStoresOnlyTokens() async throws {
  let store = MemoryTokens()
  let transport = ScriptedTransport { _ in json(#"{"accessToken":"a","refreshToken":"r"}"#) }
  let service = FellowAidenService(tokenStore: store, transport: transport)
  try await service.login(
    email: "HUGO@example.invalid", password: "synthetic-password", timezone: "America/Maceio")
  #expect(await store.load() == SessionTokens(accessToken: "a", refreshToken: "r"))
  let requests = await transport.requests
  let body =
    try JSONSerialization.jsonObject(with: #require(requests.first?.httpBody)) as! [String: Any]
  #expect(body["email"] as? String == "hugo@example.invalid")
  #expect(requests.first?.url?.path == "/v2/auth/login")
  #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func nestedStateIsAuthoritativeAndAbsentIsUnknown() async throws {
  let transport = ScriptedTransport { request in
    if request.url?.path.contains("a1") == true {
      return json(#"{"id":"a1","state":null,"brewing":true}"#)
    }
    if request.url?.path.contains("a2") == true {
      return json(#"{"id":"a2","state":{"value":"p2"},"brewing":false}"#)
    }
    return json(#"{"id":"a3"}"#)
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  #expect(try await service.restoreSession())
  #expect(try await service.device(id: "a1").phase == .idle)
  #expect(try await service.device(id: "a2").phase == .pulse)
  #expect(try await service.device(id: "a3").phase == .unknown)
}

@Test func mixedInventoryProbesEveryCandidateAndPreservesPartialIdentity() async throws {
  let transport = ScriptedTransport { request in
    let path = request.url!.path
    if path == "/v2/devices" {
      return json(
        #"[{"id":"espresso","displayName":"Espresso"},{"id":"a1","displayName":"Kitchen","firmwareVersion":"1.5.16"},{"id":"a2","displayName":"Office"}]"#
      )
    }
    if path.contains("espresso") { return json("{}", status: 404) }
    if path.hasSuffix("profiles") || path.hasSuffix("schedules") { return json("[]") }
    return json(#"{"id":"a1","state":null}"#)
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  let devices = try await service.devices()
  #expect(devices.map(\.id) == ["a1", "a2"])
  let detail = try await service.device(id: "a1")
  #expect(detail.name == "Kitchen")
  #expect(detail.firmwareVersion == "1.5.16")
  #expect(detail.isConnected == nil)
  let requests = await transport.requests
  #expect(requests.first?.url?.query == "dataType=real")
  #expect(requests.last?.url?.query == "dataType=real")
}

@Test func wrongProfileLinksNeverReachNetwork() async throws {
  let transport = ScriptedTransport { _ in json("{}") }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  for link in [
    "https://evil.example/p/abc", "https://brew.link.evil.example/p/abc", "http://brew.link/p/abc",
    "https://brew.link/p/abc/other", "https://user:pass@brew.link/p/abc",
  ] {
    await #expect(throws: AidenError.invalidLink) {
      try await service.importProfile(deviceID: "a1", link: link)
    }
  }
  #expect(await transport.requests.isEmpty)
}

@Test func remoteStartReadsFreshStateAndSendsNoBodyExactlyOnce() async throws {
  let transport = ScriptedTransport { request in
    request.httpMethod == "GET" ? json(safeDeviceJSON) : json("{}")
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  try await service.startInstantBrew(deviceID: "a1")
  let requests = await transport.requests
  #expect(requests.map(\.httpMethod) == ["GET", "PATCH"])
  #expect(requests.last?.url?.path == "/v2/devices/a1/start")
  #expect(requests.last?.url?.query == "confirm=true")
  #expect(requests.last?.httpBody == nil)
}

@Test func read401RefreshesOnceAndPersistsRotation() async throws {
  let transport = ScriptedTransport { request in
    if request.url?.path.hasSuffix("refresh-token") == true {
      return json(#"{"accessToken":"rotated","refreshToken":"rotated-refresh"}"#)
    }
    if request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access" {
      return json("{}", status: 401)
    }
    return json(#"{"id":"a1","state":null}"#)
  }
  let store = MemoryTokens(testTokens)
  let service = FellowAidenService(tokenStore: store, transport: transport)
  _ = try await service.restoreSession()
  #expect(try await service.device(id: "a1").phase == .idle)
  #expect(await store.load()?.refreshToken == "rotated-refresh")
  #expect(await transport.requests.count == 3)
}

@Test func writeTimeoutIsUncertainAndNeverReplayed() async throws {
  let transport = ScriptedTransport { request in
    if request.httpMethod == "GET" { return json(safeDeviceJSON) }
    throw URLError(.timedOut)
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  await #expect(throws: AidenError.uncertainResult) {
    try await service.startInstantBrew(deviceID: "a1")
  }
  #expect(await transport.requests.count == 2)
}

actor AsyncGate {
  private var entered = false
  private var waiter: CheckedContinuation<Void, Never>?
  private var blocked: [CheckedContinuation<Void, Never>] = []
  func pause() async {
    entered = true
    waiter?.resume()
    waiter = nil
    await withCheckedContinuation { blocked.append($0) }
  }
  func waitForEntry() async {
    if entered { return }
    await withCheckedContinuation { waiter = $0 }
  }
  func release() {
    for c in blocked { c.resume() }
    blocked = []
  }
}

@Test func concurrent401ReadsShareOneRefresh() async throws {
  let gate = AsyncGate()
  let transport = ScriptedTransport { request in
    if request.url?.path.hasSuffix("refresh-token") == true {
      await gate.pause()
      return json(#"{"accessToken":"new","refreshToken":"rotated"}"#)
    }
    if request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access" {
      return json("{}", status: 401)
    }
    return json(#"{"id":"a1","state":null}"#)
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  let one = Task { try await service.device(id: "a1") }
  await gate.waitForEntry()
  let two = Task { try await service.device(id: "a1") }
  // The second unauthorized read enters the shared refresh while the first is suspended.
  while await transport.requests.filter({ $0.httpMethod == "GET" }).count < 2 { await Task.yield() }
  await gate.release()
  #expect(try await one.value.phase == .idle)
  #expect(try await two.value.phase == .idle)
  #expect(
    await transport.requests.filter({ $0.url?.path.hasSuffix("refresh-token") == true }).count == 1)
}

@Test func logoutRejectsLateRefreshAndCannotRestorePersistedTokens() async throws {
  let gate = AsyncGate()
  let store = MemoryTokens(testTokens)
  let transport = ScriptedTransport { request in
    if request.url?.path.hasSuffix("refresh-token") == true {
      await gate.pause()
      return json(#"{"accessToken":"late","refreshToken":"late-refresh"}"#)
    }
    return json("{}", status: 401)
  }
  let service = FellowAidenService(tokenStore: store, transport: transport)
  _ = try await service.restoreSession()
  let read = Task { try await service.device(id: "a1") }
  await gate.waitForEntry()
  try await service.logout()
  await gate.release()
  await #expect(throws: AidenError.sessionChanged) { try await read.value }
  #expect(await store.load() == nil)
  #expect(await store.saved.isEmpty)
}

@Test func logoutRejectsLateLogin() async throws {
  let gate = AsyncGate()
  let store = MemoryTokens()
  let transport = ScriptedTransport { _ in
    await gate.pause()
    return json(#"{"accessToken":"late","refreshToken":"r"}"#)
  }
  let service = FellowAidenService(tokenStore: store, transport: transport)
  let login = Task {
    try await service.login(email: "test@example.invalid", password: "synthetic", timezone: "UTC")
  }
  await gate.waitForEntry()
  try await service.logout()
  await gate.release()
  await #expect(throws: AidenError.sessionChanged) { try await login.value }
  #expect(await store.load() == nil)
}

@Test func repeatedRead401InvalidatesSessionWithoutLoop() async throws {
  let transport = ScriptedTransport { request in
    if request.url?.path.hasSuffix("refresh-token") == true {
      return json(#"{"accessToken":"new","refreshToken":"new-refresh"}"#)
    }
    return json("{\"message\":\"secret internal sql\"}", status: 401)
  }
  let store = MemoryTokens(testTokens)
  let service = FellowAidenService(tokenStore: store, transport: transport)
  _ = try await service.restoreSession()
  await #expect(throws: AidenError.authentication) { try await service.device(id: "a1") }
  #expect(await transport.requests.count == 3)
  #expect(await store.load() == nil)
  await #expect(throws: AidenError.authentication) { try await service.device(id: "a1") }
  #expect(await transport.requests.count == 3)
}

@Test func write401NeverRefreshesOrReplays() async throws {
  let transport = ScriptedTransport { request in
    request.httpMethod == "GET" ? json(safeDeviceJSON) : json("{}", status: 401)
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  await #expect(throws: AidenError.authentication) {
    try await service.startInstantBrew(deviceID: "a1")
  }
  #expect(await transport.requests.map(\.httpMethod) == ["GET", "PATCH"])
}

@Test func rateLimitHonorsRetryAfterAndSanitizesResponse() async throws {
  let transport = ScriptedTransport { _ in
    json(
      #"{"message":"sql and tokens must stay hidden"}"#, status: 429,
      headers: ["Retry-After": "120"])
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  await #expect(throws: AidenError.rateLimited(seconds: 120)) { try await service.device(id: "a1") }
  do {
    _ = try await service.device(id: "a1")
    Issue.record("Expected cooldown")
  } catch {
    #expect(error.localizedDescription.contains("segundos"))
    #expect(!error.localizedDescription.contains("sql"))
  }
  #expect(await transport.requests.count == 1)
}

@Test func importedProfileUsesValidatedAllowlistStrippingServerFields() async throws {
  let payload =
    #"{"id":"server-id","createdAt":123,"folder":"server-folder","instantBrew":true,"extra":"discard","profileType":0,"title":"Test coffee","ratio":16,"bloomEnabled":true,"bloomRatio":2,"bloomDuration":30,"bloomTemperature":93,"ssPulsesEnabled":true,"ssPulsesNumber":2,"ssPulsesInterval":20,"ssPulseTemperatures":[93,93],"batchPulsesEnabled":true,"batchPulsesNumber":2,"batchPulsesInterval":20,"batchPulseTemperatures":[93,93]}"#
  let transport = ScriptedTransport { request in
    request.httpMethod == "GET" ? json(payload) : json("{}", status: 201)
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  try await service.importProfile(deviceID: "a1", link: "https://brew.link/p/abc/aiden")
  let requests = await transport.requests
  #expect(requests.first?.url?.path == "/v2/shared/aiden/abc")
  #expect(requests.last?.url?.path == "/v2/devices/a1/profiles")
  let body =
    try JSONSerialization.jsonObject(with: #require(requests.last?.httpBody)) as! [String: Any]
  #expect(body["id"] == nil)
  #expect(body["createdAt"] == nil)
  #expect(body["extra"] == nil)
  #expect(body["instantBrew"] == nil)
  #expect(body["title"] as? String == "Test coffee")
}

@Test func createScheduleUsesDeviceTimezoneAndVerifiedProfile() async throws {
  let transport = ScriptedTransport { request in
    if request.url!.path.hasSuffix("profiles") { return json(#"[{"id":"p1","title":"Light"}]"#) }
    if request.httpMethod == "GET" { return json(safeDeviceJSON) }
    return json("{}", status: 201)
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  try await service.createSchedule(
    deviceID: "a1",
    draft: ScheduleDraft(
      days: [true, false, false, false, false, false, false], secondFromStartOfTheDay: 7 * 3600,
      amountOfWater: 500, profileId: "p1"))
  let requests = await transport.requests
  #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST"])
  let body =
    try JSONSerialization.jsonObject(with: #require(requests.last?.httpBody)) as! [String: Any]
  #expect(body["secondFromStartOfTheDay"] as? Int == 25200)
  #expect(body["timezone"] == nil)
  #expect(body["id"] == nil)
  await #expect(throws: AidenError.invalidSchedule) {
    try await service.createSchedule(
      deviceID: "a1",
      draft: ScheduleDraft(
        days: Array(repeating: true, count: 7), secondFromStartOfTheDay: 3600, amountOfWater: 500,
        profileId: "p9"))
  }
  #expect(await transport.requests.filter { $0.httpMethod == "POST" }.count == 1)
}

@Test func scheduleToggleAndDeleteValidateDeviceOwnership() async throws {
  let transport = ScriptedTransport { request in
    request.httpMethod == "GET"
      ? json(
        #"[{"id":"s1","days":[false,true,true,true,true,true,false],"secondFromStartOfTheDay":21600,"enabled":true,"amountOfWater":750,"profileId":"p1"}]"#
      ) : json("{}", status: 204)
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  try await service.setScheduleEnabled(deviceID: "a1", scheduleID: "s1", enabled: false)
  try await service.deleteSchedule(deviceID: "a1", scheduleID: "s1")
  await #expect(throws: AidenError.invalidSchedule) {
    try await service.deleteSchedule(deviceID: "a1", scheduleID: "other")
  }
  let requests = await transport.requests
  #expect(requests.map(\.httpMethod) == ["GET", "PATCH", "GET", "DELETE", "GET"])
  #expect(requests[1].url?.path == "/v2/devices/a1/schedules/s1")
  let body =
    try JSONSerialization.jsonObject(with: #require(requests[1].httpBody)) as! [String: Any]
  #expect(body.count == 1)
  #expect(body["enabled"] as? Bool == false)
}

@Test func startFailsClosedForBusyOfflineUnknownAndOldFirmware() async throws {
  for payload in [
    #"{"id":"a1","state":{"value":"b"}}"#, #"{"id":"a1","state":null,"isConnected":false}"#,
    #"{"id":"a1"}"#, safeDeviceJSON.replacingOccurrences(of: "1.5.16", with: "1.5.15"),
  ] {
    let transport = ScriptedTransport { _ in json(payload) }
    let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
    _ = try await service.restoreSession()
    await #expect(throws: AidenError.unsafeBrew) {
      try await service.startInstantBrew(deviceID: "a1")
    }
    #expect(await transport.requests.map(\.httpMethod) == ["GET"])
  }
}

@Test func logoutRejectsInFlightImportBeforeAnyWrite() async throws {
  let gate = AsyncGate()
  let transport = ScriptedTransport { _ in
    await gate.pause()
    return json(
      #"{"id":"server-id","profileType":0,"title":"Test coffee","ratio":16,"bloomEnabled":true,"bloomRatio":2,"bloomDuration":30,"bloomTemperature":93,"ssPulsesEnabled":true,"ssPulsesNumber":2,"ssPulsesInterval":20,"ssPulseTemperatures":[93,93],"batchPulsesEnabled":true,"batchPulsesNumber":2,"batchPulsesInterval":20,"batchPulseTemperatures":[93,93]}"#
    )
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  let write = Task {
    try await service.importProfile(deviceID: "a1", link: "https://brew.link/p/abc")
  }
  await gate.waitForEntry()
  try await service.logout()
  await gate.release()
  await #expect(throws: AidenError.sessionChanged) { try await write.value }
  #expect(await transport.requests.count == 1)
  #expect(await transport.requests.first?.httpMethod == "GET")
}

@Test func concurrentStartCannotSendTwoPhysicalCommands() async throws {
  let gate = AsyncGate()
  let transport = ScriptedTransport { request in
    if request.httpMethod == "GET" {
      await gate.pause()
      return json(safeDeviceJSON)
    }
    return json("{}")
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  let one = Task { try await service.startInstantBrew(deviceID: "a1") }
  await gate.waitForEntry()
  await #expect(throws: AidenError.unsafeBrew) {
    try await service.startInstantBrew(deviceID: "a1")
  }
  await gate.release()
  try await one.value
  #expect(await transport.requests.filter { $0.httpMethod == "PATCH" }.count == 1)
}

@Test func invalidProfileImportStopsBeforePost() async throws {
  let transport = ScriptedTransport { _ in json(#"{"title":"partial","ratio":16}"#) }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  await #expect(throws: AidenError.invalidProfile) {
    try await service.importProfile(deviceID: "a1", link: "https://brew.link/p/abc")
  }
  #expect(await transport.requests.map(\.httpMethod) == ["GET"])
}

@Test func unsupportedRouteAndNetworkFailureAreNotConflated() async throws {
  let transport = ScriptedTransport { request in
    if request.url?.path == "/v2/devices" { return json(#"[{"id":"a1"}]"#) }
    throw URLError(.notConnectedToInternet)
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  await #expect(throws: AidenError.unavailable) { try await service.devices() }
}

@Test func unknownTimezonePreventsScheduleCreation() async throws {
  let transport = ScriptedTransport { _ in json(#"{"id":"a1"}"#) }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  await #expect(throws: AidenError.invalidSchedule) {
    try await service.createSchedule(
      deviceID: "a1",
      draft: ScheduleDraft(
        days: Array(repeating: true, count: 7), secondFromStartOfTheDay: 3600, amountOfWater: 500,
        profileId: "p1"))
  }
  #expect(await transport.requests.map(\.httpMethod) == ["GET"])
}

@Test func detailRejectsWrongDeviceAndMalformedPath() async throws {
  let transport = ScriptedTransport { _ in json(#"{"id":"other","state":null}"#) }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  await #expect(throws: AidenError.invalidResponse) { try await service.device(id: "../account") }
  #expect(await transport.requests.isEmpty)
  await #expect(throws: AidenError.invalidResponse) { try await service.device(id: "a1") }
}

@Test func rejectedLoginAndMalformedTokensNeverPersist() async throws {
  for response in [
    json(#"{"message":"private internal path"}"#, status: 401), json(#"{"accessToken":"a"}"#),
  ] {
    let store = MemoryTokens()
    let service = FellowAidenService(
      tokenStore: store, transport: ScriptedTransport { _ in response })
    do {
      try await service.login(email: "test@example.invalid", password: "synthetic", timezone: "UTC")
      Issue.record("Login must reject incompatible response")
    } catch { #expect(!error.localizedDescription.contains("internal path")) }
    #expect(await store.load() == nil)
  }
}

@Test func emptyInventoryIsValidAndUnknownSelectedDeviceIsRejected() async throws {
  let transport = ScriptedTransport { _ in json("[]") }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  #expect(try await service.devices().isEmpty)
  await #expect(throws: AidenError.unsupportedDevice) { try await service.device(id: "other") }
  #expect(await transport.requests.count == 1)
}

@Test func sharingReturnsOnlyVerifiedFellowLink() async throws {
  let transport = ScriptedTransport { request in
    if request.httpMethod == "GET" { return json(#"[{"id":"p1","title":"Coffee"}]"#) }
    return json(#"{"link":"https://brew.link/p/abc"}"#)
  }
  let service = FellowAidenService(tokenStore: MemoryTokens(testTokens), transport: transport)
  _ = try await service.restoreSession()
  #expect(
    try await service.shareProfile(deviceID: "a1", profileID: "p1").absoluteString
      == "https://brew.link/p/abc")
  await #expect(throws: AidenError.invalidProfile) {
    try await service.shareProfile(deviceID: "a1", profileID: "p9")
  }
  #expect(await transport.requests.filter { $0.httpMethod == "POST" }.count == 1)
}

actor DelayedSaveTokens: TokenStore {
  let gate: AsyncGate
  var value: SessionTokens?
  var operations: [String] = []
  init(gate: AsyncGate) { self.gate = gate }
  func load() -> SessionTokens? { value }
  func save(_ tokens: SessionTokens) async {
    await gate.pause()
    value = tokens
    operations.append("save")
  }
  func clear() {
    value = nil
    operations.append("clear")
  }
}

@Test func logoutClearIsOrderedAfterAnAlreadyStartedTokenSave() async throws {
  let gate = AsyncGate()
  let store = DelayedSaveTokens(gate: gate)
  let transport = ScriptedTransport { _ in json(#"{"accessToken":"a","refreshToken":"r"}"#) }
  let session = AidenSession(store: store, transport: transport)
  let login = Task {
    try await session.login(email: "test@example.invalid", password: "synthetic", timezone: "UTC")
  }
  await gate.waitForEntry()
  let logout = Task { try await session.logout() }
  // Session logout must be enqueued before the delayed token save completes.
  while await session.currentGeneration() < 2 { await Task.yield() }
  await gate.release()
  try await logout.value
  await #expect(throws: AidenError.sessionChanged) { try await login.value }
  #expect(await store.load() == nil)
  #expect(await store.operations == ["clear", "save", "clear"])
}
