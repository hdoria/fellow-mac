import Foundation

public actor FellowAidenService: AidenService {
  private let session: AidenSession
  private var inventory: [String: Brewer] = [:]
  private var inventoryKnown = false
  private var activeStart: Set<String> = []
  private var generation: UInt64 = 0
  public init(tokenStore: any TokenStore, transport: any HTTPTransport = URLSessionTransport()) {
    session = AidenSession(store: tokenStore, transport: transport)
  }
  public func restoreSession() async throws -> Bool { try await session.restore() }
  public func login(email: String, password: String, timezone: String) async throws {
    generation &+= 1
    inventory = [:]
    inventoryKnown = false
    activeStart = []
    try await session.login(email: email, password: password, timezone: timezone)
  }
  public func logout() async throws {
    generation &+= 1
    inventory = [:]
    inventoryKnown = false
    activeStart = []
    try await session.logout()
  }
  public func devices() async throws -> [Brewer] {
    let operation = try await beginOperation()
    let expected = operation.serviceGeneration
    let response = try await session.request(
      path: "devices?dataType=real", expectedGeneration: operation.sessionGeneration)
    let payloads: [BrewerPayload] = try decode(response.data)
    var result: [Brewer] = []
    var seen: Set<String> = []
    let unsupported: Set<Int> = [400, 404, 405, 422]
    for payload in payloads {
      let candidate = try payload.brewer()
      let id = try component(candidate.id)
      guard !seen.contains(id) else { throw AidenError.invalidResponse }
      seen.insert(id)
      // Route capability identifies Aiden; names and model strings are not reliable discriminators.
      let profiles = try await session.request(
        path: "devices/\(id)/profiles", acceptedStatuses: unsupported,
        expectedGeneration: operation.sessionGeneration)
      try assertGeneration(expected)
      if unsupported.contains(profiles.status) { continue }
      _ = try objects(profiles.data)
      let schedules = try await session.request(
        path: "devices/\(id)/schedules", acceptedStatuses: unsupported,
        expectedGeneration: operation.sessionGeneration)
      try assertGeneration(expected)
      if unsupported.contains(schedules.status) { continue }
      _ = try objects(schedules.data)
      result.append(candidate)
    }
    guard generation == expected else { throw AidenError.sessionChanged }
    inventory = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
    inventoryKnown = true
    return result
  }
  public func device(id: String) async throws -> Brewer {
    let operation = try await beginOperation()
    let expected = operation.serviceGeneration
    let id = try deviceComponent(id)
    let response = try await session.request(
      path: "devices/\(id)?dataType=real", expectedGeneration: operation.sessionGeneration)
    let payload: BrewerPayload = try decode(response.data)
    let result = try payload.brewer(fallbackID: id, previous: inventory[id])
    guard result.id == id else { throw AidenError.invalidResponse }
    guard generation == expected else { throw AidenError.sessionChanged }
    if inventoryKnown { inventory[id] = result }
    return result
  }
  public func profiles(deviceID: String) async throws -> [BrewProfile] {
    let operation = try await beginOperation()
    let expected = operation.serviceGeneration
    let id = try deviceComponent(deviceID)
    let response = try await session.request(
      path: "devices/\(id)/profiles", expectedGeneration: operation.sessionGeneration)
    try assertGeneration(expected)
    return try objects(response.data).map { fields in
      guard let id = fields["id"]?.string, let title = fields["title"]?.string else {
        throw AidenError.invalidResponse
      }
      return BrewProfile(
        id: id, title: title, ratio: fields["ratio"]?.number,
        bloomTemperature: fields["bloomTemperature"]?.number,
        bloomDuration: fields["bloomDuration"]?.int)
    }
  }
  public func schedules(deviceID: String) async throws -> [BrewSchedule] {
    let operation = try await beginOperation()
    let expected = operation.serviceGeneration
    let id = try deviceComponent(deviceID)
    let response = try await session.request(
      path: "devices/\(id)/schedules", expectedGeneration: operation.sessionGeneration)
    try assertGeneration(expected)
    return try objects(response.data).map { fields in
      guard let id = fields["id"]?.string, let daysJSON = fields["days"]?.array,
        let second = fields["secondFromStartOfTheDay"]?.int, let enabled = fields["enabled"]?.bool,
        let amount = fields["amountOfWater"]?.int, let profile = fields["profileId"]?.string
      else { throw AidenError.invalidResponse }
      let days = daysJSON.compactMap(\.bool)
      guard days.count == 7, daysJSON.count == 7, (0..<86400).contains(second),
        (150...1500).contains(amount)
      else { throw AidenError.invalidResponse }
      return BrewSchedule(
        id: id, days: days, secondFromStartOfTheDay: second, enabled: enabled,
        amountOfWater: amount, profileId: profile)
    }
  }
  public func importProfile(deviceID: String, link: String) async throws {
    let operation = try await beginOperation()
    let expected = operation.serviceGeneration
    let sharedID = try Self.sharedID(link)
    let id = try deviceComponent(deviceID)
    let response = try await session.request(
      path: "shared/aiden/\(sharedID)", expectedGeneration: operation.sessionGeneration)
    try assertGeneration(expected)
    let fields: [String: JSONValue] = try decode(response.data)
    let writable = try Self.validateProfile(fields)
    _ = try await session.request(
      path: "devices/\(id)/profiles", method: "POST", body: JSONEncoder().encode(writable),
      expectedGeneration: operation.sessionGeneration)
  }
  public func shareProfile(deviceID: String, profileID: String) async throws -> URL {
    let operation = try await beginOperation()
    let expected = operation.serviceGeneration
    let id = try deviceComponent(deviceID)
    let profileID = try component(profileID)
    guard try await profiles(deviceID: id).contains(where: { $0.id == profileID }) else {
      throw AidenError.invalidProfile
    }
    try assertGeneration(expected)
    let response = try await session.request(
      path: "devices/\(id)/profiles/\(profileID)/share", method: "POST",
      expectedGeneration: operation.sessionGeneration)
    try assertGeneration(expected)
    let value: JSONValue = try decode(response.data)
    guard let link = value.string ?? value.object?["url"]?.string ?? value.object?["link"]?.string,
      let url = URL(string: link), (try? Self.sharedID(link)) != nil
    else { throw AidenError.invalidResponse }
    return url
  }
  public func createSchedule(deviceID: String, draft: ScheduleDraft) async throws {
    let operation = try await beginOperation()
    let expected = operation.serviceGeneration
    try draft.validate()
    let id = try deviceComponent(deviceID)
    let brewer = try await device(id: id)
    try assertGeneration(expected)
    guard let timezone = brewer.timezone, TimeZone(identifier: timezone) != nil else {
      throw AidenError.invalidSchedule
    }
    guard try await profiles(deviceID: id).contains(where: { $0.id == draft.profileId }) else {
      throw AidenError.invalidSchedule
    }
    try assertGeneration(expected)
    _ = try await session.request(
      path: "devices/\(id)/schedules", method: "POST", body: JSONEncoder().encode(draft),
      expectedGeneration: operation.sessionGeneration)
  }
  public func setScheduleEnabled(deviceID: String, scheduleID: String, enabled: Bool) async throws {
    let operation = try await beginOperation()
    let expected = operation.serviceGeneration
    let id = try deviceComponent(deviceID)
    let scheduleID = try component(scheduleID)
    guard try await schedules(deviceID: id).contains(where: { $0.id == scheduleID }) else {
      throw AidenError.invalidSchedule
    }
    try assertGeneration(expected)
    _ = try await session.request(
      path: "devices/\(id)/schedules/\(scheduleID)", method: "PATCH",
      body: JSONEncoder().encode(["enabled": enabled]),
      expectedGeneration: operation.sessionGeneration)
  }
  public func deleteSchedule(deviceID: String, scheduleID: String) async throws {
    let operation = try await beginOperation()
    let expected = operation.serviceGeneration
    let id = try deviceComponent(deviceID)
    let scheduleID = try component(scheduleID)
    guard try await schedules(deviceID: id).contains(where: { $0.id == scheduleID }) else {
      throw AidenError.invalidSchedule
    }
    try assertGeneration(expected)
    _ = try await session.request(
      path: "devices/\(id)/schedules/\(scheduleID)", method: "DELETE",
      expectedGeneration: operation.sessionGeneration)
  }
  public func startInstantBrew(deviceID: String) async throws {
    let id = try deviceComponent(deviceID)
    let operation = try await beginOperation()
    let expected = operation.serviceGeneration
    guard !activeStart.contains(id) else { throw AidenError.unsafeBrew }
    activeStart.insert(id)
    defer { if expected == generation { activeStart.remove(id) } }
    let brewer = try await device(id: id)
    guard expected == generation else { throw AidenError.sessionChanged }
    guard brewer.canStartInstantBrew else { throw AidenError.unsafeBrew }
    _ = try await session.request(
      path: "devices/\(id)/start?confirm=true", method: "PATCH",
      expectedGeneration: operation.sessionGeneration)
    // HTTP acceptance is deliberately not converted into a brewing state.
  }

  private func component(_ value: String) throws -> String {
    guard value.count <= 200,
      value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    else { throw AidenError.invalidResponse }
    return value
  }
  private struct Operation {
    let serviceGeneration: UInt64
    let sessionGeneration: UInt64
  }
  private func beginOperation() async throws -> Operation {
    let expected = generation
    let sessionGeneration = await session.currentGeneration()
    try assertGeneration(expected)
    return Operation(serviceGeneration: expected, sessionGeneration: sessionGeneration)
  }
  private func assertGeneration(_ expected: UInt64) throws {
    guard expected == generation else { throw AidenError.sessionChanged }
  }
  private func deviceComponent(_ value: String) throws -> String {
    let id = try component(value)
    if inventoryKnown && inventory[id] == nil { throw AidenError.unsupportedDevice }
    return id
  }
  private func decode<T: Decodable>(_ data: Data) throws -> T {
    do { return try JSONDecoder().decode(T.self, from: data) } catch {
      throw AidenError.invalidResponse
    }
  }
  private func objects(_ data: Data) throws -> [[String: JSONValue]] { try decode(data) }
  private static func sharedID(_ link: String) throws -> String {
    guard let components = URLComponents(string: link), components.scheme == "https",
      components.host?.lowercased() == "brew.link", components.port == nil,
      components.user == nil, components.password == nil,
      components.query == nil, components.fragment == nil
    else { throw AidenError.invalidLink }
    let parts = components.path.split(separator: "/")
    guard parts.count == 2 || parts.count == 3, parts[0] == "p",
      parts[1].range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil,
      parts.count == 2 || parts[2] == "aiden"
    else { throw AidenError.invalidLink }
    return String(parts[1])
  }
  private static func validateProfile(_ fields: [String: JSONValue]) throws -> [String: JSONValue] {
    let keys = [
      "profileType", "title", "ratio", "bloomEnabled", "bloomRatio", "bloomDuration",
      "bloomTemperature",
      "ssPulsesEnabled", "ssPulsesNumber", "ssPulsesInterval", "ssPulseTemperatures",
      "batchPulsesEnabled", "batchPulsesNumber", "batchPulsesInterval", "batchPulseTemperatures",
    ]
    guard keys.allSatisfy({ fields[$0] != nil }), let title = fields["title"]?.string,
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 50,
      fields["profileType"]?.int != nil, fields["bloomEnabled"]?.bool != nil,
      fields["ssPulsesEnabled"]?.bool != nil, fields["batchPulsesEnabled"]?.bool != nil
    else { throw AidenError.invalidProfile }
    func halfStep(_ key: String, _ bounds: ClosedRange<Double>) -> Bool {
      guard let value = fields[key]?.number else { return false }
      return bounds.contains(value) && (value * 2).rounded() == value * 2
    }
    guard halfStep("ratio", 14...20), halfStep("bloomRatio", 1...3),
      halfStep("bloomTemperature", 50...99),
      let duration = fields["bloomDuration"]?.int, (1...120).contains(duration)
    else { throw AidenError.invalidProfile }
    for prefix in ["ss", "batch"] {
      guard let count = fields[prefix + "PulsesNumber"]?.int, (1...10).contains(count),
        let interval = fields[prefix + "PulsesInterval"]?.int, (5...60).contains(interval),
        let temperatures = fields[prefix + "PulseTemperatures"]?.array, !temperatures.isEmpty,
        temperatures.count <= 10,
        temperatures.allSatisfy({ value in
          guard let n = value.number else { return false }
          return (50...99).contains(n) && (n * 2).rounded() == n * 2
        })
      else { throw AidenError.invalidProfile }
    }
    return fields.filter { keys.contains($0.key) }
  }
}
