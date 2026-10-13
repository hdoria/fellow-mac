import AidenCore
import Foundation

/// Independent in-memory service. It has no transport or access to account credentials.
actor DemoService: AidenService {
  private var scenario: DemoScenario = .idle
  private var storedProfiles = [
    BrewProfile(
      id: "plocal1", title: "Etiópia · claro", ratio: 16, bloomTemperature: 93, bloomDuration: 45),
    BrewProfile(
      id: "plocal2", title: "Brasil · médio", ratio: 15, bloomTemperature: 92, bloomDuration: 30),
    BrewProfile(
      id: "plocal3", title: "Intenso · escuro", ratio: 14, bloomTemperature: 88, bloomDuration: 30),
  ]
  private var storedSchedules = [
    BrewSchedule(
      id: "demo-morning", days: [false, true, true, true, true, true, false],
      secondFromStartOfTheDay: 7 * 3600 + 30 * 60, enabled: true, amountOfWater: 600,
      profileId: "plocal1")
  ]
  func setScenario(_ scenario: DemoScenario) { self.scenario = scenario }
  func restoreSession() async throws -> Bool { true }
  func login(email: String, password: String, timezone: String) async throws {}
  func logout() async throws {}
  func devices() async throws -> [Brewer] {
    scenario == .noDevices ? [] : [try await device(id: "demo-aiden")]
  }
  func device(id: String) async throws -> Brewer {
    guard id == "demo-aiden", scenario != .noDevices else { throw AidenError.unsupportedDevice }
    guard scenario != .cloudError && scenario != .stale else { throw AidenError.unavailable }
    return Brewer(
      id: id, name: "Aiden da cozinha", firmwareVersion: "1.5.16", timezone: "America/Maceio",
      isConnected: scenario != .offline, phase: scenario == .brewing ? .brewing : .idle,
      missingWater: false, lidClosed: true, carafePresent: true, singleBrewBasketPresent: true,
      batchBrewBasketPresent: false, cleaning: false, rinsing: false, hasError: false,
      telemetryAt: Date(), instantProfileID: "plocal1", instantWaterQuantity: 300,
      currentProfileID: scenario == .brewing ? "plocal1" : nil)
  }
  func profiles(deviceID: String) async throws -> [BrewProfile] { storedProfiles }
  func schedules(deviceID: String) async throws -> [BrewSchedule] { storedSchedules }
  func importProfile(deviceID: String, link: String) async throws {
    guard let url = URLComponents(string: link), url.scheme == "https",
      url.host?.lowercased() == "brew.link", url.port == nil, url.user == nil, url.password == nil,
      url.query == nil, url.fragment == nil
    else { throw AidenError.invalidLink }
    let parts = url.path.split(separator: "/")
    guard parts.count == 2 || parts.count == 3, parts.first == "p",
      parts[1].range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil,
      parts.count == 2 || parts[2] == "aiden"
    else { throw AidenError.invalidLink }
    storedProfiles.append(
      BrewProfile(
        id: "plocal\(storedProfiles.count + 1)", title: "Perfil importado (simulado)", ratio: 16))
  }
  func shareProfile(deviceID: String, profileID: String) async throws -> URL {
    URL(string: "https://brew.link/p/Demo123/aiden")!
  }
  func createSchedule(deviceID: String, draft: ScheduleDraft) async throws {
    try draft.validate()
    storedSchedules.append(
      BrewSchedule(
        id: UUID().uuidString, days: draft.days,
        secondFromStartOfTheDay: draft.secondFromStartOfTheDay, enabled: draft.enabled,
        amountOfWater: draft.amountOfWater, profileId: draft.profileId))
  }
  func setScheduleEnabled(deviceID: String, scheduleID: String, enabled: Bool) async throws {
    guard let index = storedSchedules.firstIndex(where: { $0.id == scheduleID }) else {
      throw AidenError.invalidSchedule
    }
    let previous = storedSchedules[index]
    storedSchedules[index] = BrewSchedule(
      id: previous.id, days: previous.days,
      secondFromStartOfTheDay: previous.secondFromStartOfTheDay, enabled: enabled,
      amountOfWater: previous.amountOfWater, profileId: previous.profileId)
  }
  func deleteSchedule(deviceID: String, scheduleID: String) async throws {
    storedSchedules.removeAll { $0.id == scheduleID }
  }
  func startInstantBrew(deviceID: String) async throws {
    guard try await device(id: deviceID).canStartInstantBrew else { throw AidenError.unsafeBrew }
    scenario = .brewing
  }
}
