import AidenCore
import XCTest

@testable import FellowMac

@MainActor
final class AppModelTests: XCTestCase {
  func testTwoDevicesRequireExplicitSelection() async {
    let model = AppModel(service: FixtureService(twoDevices: true), pollingEnabled: false)
    await model.login(email: "test@example.com", password: "ephemeral")
    XCTAssertTrue(model.isConnected)
    XCTAssertEqual(model.devices.count, 2)
    XCTAssertNil(model.selectedDeviceID)
    XCTAssertNil(model.snapshot)
    await model.selectDevice("kitchen")
    XCTAssertEqual(model.snapshot?.id, "kitchen")
  }

  func testLogoutDiscardsLateDeviceSnapshot() async {
    let service = FixtureService(delayDevice: true)
    let model = AppModel(service: service, pollingEnabled: false)
    let login = Task { await model.login(email: "test@example.com", password: "ephemeral") }
    while !(await service.deviceRequested) { await Task.yield() }
    await model.logout()
    await service.releaseDevice()
    await login.value
    XCTAssertFalse(model.isConnected)
    XCTAssertNil(model.snapshot)
    XCTAssertTrue(model.devices.isEmpty)
    XCTAssertNil(model.lastFetchedAt)
  }

  func testUncertainStartCannotBeRepeatedWithoutFreshConfirmation() async {
    let service = FixtureService()
    let model = AppModel(service: service, pollingEnabled: false)
    await model.login(email: "test@example.com", password: "ephemeral")
    model.experimentalBrewEnabled = true
    model.prepareBrewConfirmation()
    XCTAssertTrue(model.showBrewConfirmation)
    await model.confirmBrew()
    await model.confirmBrew()
    let starts = await service.startCount
    XCTAssertEqual(starts, 1)
    XCTAssertFalse(model.showBrewConfirmation)
    XCTAssertNotNil(model.errorMessage)
  }

  func testDemoModeClearsRealAccountSnapshots() async {
    let model = AppModel(service: FixtureService(), pollingEnabled: false)
    await model.login(email: "test@example.com", password: "ephemeral")
    await model.enterDemo()
    XCTAssertTrue(model.isDemo)
    XCTAssertEqual(model.snapshot?.id, "demo-aiden")
    await model.setDemoScenario(.noDevices)
    XCTAssertNil(model.snapshot)
    XCTAssertTrue(model.devices.isEmpty)
  }

  func testEnteringDemoPreservesSavedRealSession() async {
    let service = FixtureService()
    let model = AppModel(service: service, pollingEnabled: false)
    await model.enterDemo()
    let logouts = await service.logoutCount
    XCTAssertEqual(logouts, 0)
  }

  func testAcceptedBrewRemainsPendingWhileCloudStillReportsIdle() async {
    let service = FixtureService(startThrows: false)
    let model = AppModel(service: service, pollingEnabled: false)
    await model.login(email: "test@example.com", password: "ephemeral")
    model.experimentalBrewEnabled = true
    model.prepareBrewConfirmation()
    await model.confirmBrew()
    XCTAssertFalse(model.canOfferBrew)
    model.prepareBrewConfirmation()
    await model.confirmBrew()
    let starts = await service.startCount
    XCTAssertEqual(starts, 1)
  }

  func testDemoCanCreateScheduleWithDisplayedProfileAndImportSharedLink() async throws {
    let model = AppModel(service: FixtureService(), pollingEnabled: false)
    await model.enterDemo()
    let profile = try XCTUnwrap(model.profiles.first)
    let originalSchedules = model.schedules.count
    await model.createSchedule(
      ScheduleDraft(
        days: [true, false, false, false, false, false, false], secondFromStartOfTheDay: 8 * 3600,
        amountOfWater: 300, profileId: profile.id))
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.schedules.count, originalSchedules + 1)
    let sharedURL = await model.shareProfile(profile)
    let shared = try XCTUnwrap(sharedURL)
    XCTAssertEqual(shared.host, "brew.link")
    let originalProfiles = model.profiles.count
    await model.importProfile(link: shared.absoluteString)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.profiles.count, originalProfiles + 1)
  }

  func testEmptySelectionInventoryRefreshIsSingleFlight() async {
    let service = FixtureService(twoDevices: true)
    let model = AppModel(service: service, pollingEnabled: false)
    await model.login(email: "test@example.com", password: "ephemeral")
    await service.holdInventory()
    let first = Task { await model.refresh() }
    while !(await service.inventoryRequested) { await Task.yield() }
    let second = Task { await model.refresh() }
    await second.value
    await service.releaseInventory()
    await first.value
    let queries = await service.inventoryCount
    XCTAssertEqual(queries, 2)
  }

  func testScheduleConfirmationCannotRetargetAfterDeviceSelectionChanges() async {
    let service = FixtureService(twoDevices: true)
    let model = AppModel(service: service, pollingEnabled: false)
    await model.login(email: "test@example.com", password: "ephemeral")
    await model.selectDevice("kitchen")
    let capturedContext = model.actionContextID
    let schedule = BrewSchedule(
      id: "same-schedule", days: [true, false, false, false, false, false, false],
      secondFromStartOfTheDay: 28800, enabled: true, amountOfWater: 300, profileId: "plocal1")
    await model.selectDevice("office")
    await model.toggleSchedule(
      schedule, expectedDeviceID: "kitchen", expectedContextID: capturedContext)
    await model.deleteSchedule(
      schedule, expectedDeviceID: "kitchen", expectedContextID: capturedContext)
    let created = await model.createSchedule(
      ScheduleDraft(
        days: schedule.days, secondFromStartOfTheDay: 28800, amountOfWater: 300,
        profileId: "plocal1"), expectedDeviceID: "kitchen", expectedContextID: capturedContext)
    XCTAssertFalse(created)
    let writes = await service.scheduleWrites
    XCTAssertEqual(writes, 0)
  }

  func testScheduleCreationReportsNotSubmittedDuringRefresh() async {
    let service = FixtureService()
    let model = AppModel(service: service, pollingEnabled: false)
    await model.login(email: "test@example.com", password: "ephemeral")
    await service.holdDevice()
    let refresh = Task { await model.refresh() }
    while !(await service.deviceRequested) { await Task.yield() }
    let created = await model.createSchedule(
      ScheduleDraft(
        days: [true, false, false, false, false, false, false], secondFromStartOfTheDay: 28800,
        amountOfWater: 300, profileId: "plocal1"))
    XCTAssertFalse(created)
    let writes = await service.scheduleWrites
    XCTAssertEqual(writes, 0)
    await service.releaseDevice()
    await refresh.value
  }

  func testDemoCloudErrorPreservesLastSnapshotAndFetchTime() async {
    let service = FixtureService()
    let model = AppModel(service: service, pollingEnabled: false)
    await model.enterDemo()
    let previous = model.snapshot
    let fetchedAt = model.lastFetchedAt
    await model.setDemoScenario(.cloudError)
    XCTAssertEqual(model.snapshot, previous)
    XCTAssertEqual(model.lastFetchedAt, fetchedAt)
    XCTAssertTrue(model.isStale)
    XCTAssertNotNil(model.errorMessage)
    model.experimentalBrewEnabled = true
    XCTAssertFalse(model.canOfferBrew)
    let queries = await service.inventoryCount
    let logouts = await service.logoutCount
    XCTAssertEqual(queries, 0)
    XCTAssertEqual(logouts, 0)
  }

  func testDemoStaleSnapshotIsMarkedOldAndCannotStartBrew() async {
    let model = AppModel(service: FixtureService(), pollingEnabled: false)
    await model.enterDemo()
    let previous = model.snapshot
    await model.setDemoScenario(.stale)
    XCTAssertEqual(model.snapshot, previous)
    XCTAssertTrue(model.isStale)
    XCTAssertNotNil(model.notice)
    model.experimentalBrewEnabled = true
    XCTAssertFalse(model.canOfferBrew)
  }

  func testDemoConnectingIsVisibleAndCompletesWithoutProductionCalls() async {
    let service = FixtureService()
    let model = AppModel(service: service, pollingEnabled: false)
    await model.enterDemo()
    let connection = Task { await model.setDemoScenario(.connecting) }
    while model.demoScenario != .connecting { await Task.yield() }
    XCTAssertTrue(model.isLoading)
    XCTAssertEqual(model.statusLabel, "Conectando")
    await connection.value
    XCTAssertEqual(model.demoScenario, .idle)
    XCTAssertFalse(model.isLoading)
    XCTAssertEqual(model.snapshot?.id, "demo-aiden")
    let queries = await service.inventoryCount
    XCTAssertEqual(queries, 0)
  }

  func testDemoConnectingCannotRestoreStateAfterLogout() async {
    let model = AppModel(service: FixtureService(), pollingEnabled: false)
    await model.enterDemo()
    let connection = Task { await model.setDemoScenario(.connecting) }
    while model.demoScenario != .connecting { await Task.yield() }
    await model.logout()
    await connection.value
    XCTAssertFalse(model.isDemo)
    XCTAssertFalse(model.isConnected)
    XCTAssertNil(model.snapshot)
    XCTAssertFalse(model.isLoading)
  }

  func testRateLimitBlocksRefreshUntilClockReachesRetryAfter() async {
    let clock = TestDateClock()
    let service = FixtureService()
    let model = AppModel(service: service, pollingEnabled: false, now: { clock.now })
    await model.login(email: "test@example.com", password: "ephemeral")
    await service.failNextDevice(AidenError.rateLimited(seconds: 10))
    await model.refresh()
    await model.refresh()
    clock.advance(9)
    await model.refresh()
    let beforeExpiry = await service.deviceCount
    XCTAssertEqual(beforeExpiry, 2)
    clock.advance(1)
    await model.refresh()
    let afterExpiry = await service.deviceCount
    XCTAssertEqual(afterExpiry, 3)
    XCTAssertFalse(model.isStale)
    XCTAssertNil(model.errorMessage)
  }

  func testPausingPollingCancelsSleepAndPreventsAnotherRead() async {
    let sleeper = ControlledSleeper()
    let service = FixtureService()
    let model = AppModel(service: service, sleep: { try await sleeper.sleep($0) })
    await model.login(email: "test@example.com", password: "ephemeral")
    for _ in 0..<1000 {
      if await sleeper.pendingCount == 1 { break }
      await Task.yield()
    }
    let initialSleeps = await sleeper.pendingCount
    XCTAssertEqual(initialSleeps, 1)
    guard initialSleeps == 1 else {
      model.pausePolling()
      return
    }
    await sleeper.advance()
    for _ in 0..<1000 {
      if await service.deviceCount == 2, await sleeper.pendingCount == 1 { break }
      await Task.yield()
    }
    let readsBeforePause = await service.deviceCount
    XCTAssertEqual(readsBeforePause, 2)
    model.pausePolling()
    for _ in 0..<1000 {
      if await sleeper.pendingCount == 0 { break }
      await Task.yield()
    }
    await sleeper.advance()
    await Task.yield()
    let readsAfterPause = await service.deviceCount
    let remainingSleeps = await sleeper.pendingCount
    XCTAssertEqual(readsAfterPause, 2)
    XCTAssertEqual(remainingSleeps, 0)
  }
}

actor FixtureService: AidenService {
  let twoDevices: Bool
  var delayDevice: Bool
  let startThrows: Bool
  var deviceRequested = false
  var deviceCount = 0
  var nextDeviceError: AidenError?
  var startCount = 0
  var logoutCount = 0
  var scheduleWrites = 0
  var inventoryCount = 0
  var inventoryRequested = false
  var holdInventoryReads = false
  var inventoryContinuation: CheckedContinuation<Void, Never>?
  var continuation: CheckedContinuation<Void, Never>?
  init(twoDevices: Bool = false, delayDevice: Bool = false, startThrows: Bool = true) {
    self.twoDevices = twoDevices
    self.delayDevice = delayDevice
    self.startThrows = startThrows
  }
  func restoreSession() async throws -> Bool { true }
  func login(email: String, password: String, timezone: String) async throws {}
  func logout() async throws { logoutCount += 1 }
  func devices() async throws -> [Brewer] {
    inventoryCount += 1
    if holdInventoryReads && !inventoryRequested {
      inventoryRequested = true
      await withCheckedContinuation { inventoryContinuation = $0 }
    }
    return twoDevices ? [brewer("kitchen"), brewer("office")] : [brewer("kitchen")]
  }
  func holdInventory() { holdInventoryReads = true }
  func releaseInventory() {
    inventoryContinuation?.resume()
    inventoryContinuation = nil
  }
  func device(id: String) async throws -> Brewer {
    deviceCount += 1
    if let error = nextDeviceError {
      nextDeviceError = nil
      throw error
    }
    if delayDevice {
      deviceRequested = true
      await withCheckedContinuation { continuation = $0 }
    }
    return brewer(id)
  }
  func releaseDevice() {
    continuation?.resume()
    continuation = nil
  }
  func holdDevice() {
    delayDevice = true
    deviceRequested = false
  }
  func failNextDevice(_ error: AidenError) { nextDeviceError = error }
  func brewer(_ id: String) -> Brewer {
    Brewer(
      id: id, firmwareVersion: "1.5.16", timezone: "America/Maceio", isConnected: true,
      phase: .idle, missingWater: false, lidClosed: true, carafePresent: true,
      singleBrewBasketPresent: true, cleaning: false, rinsing: false, hasError: false)
  }
  func profiles(deviceID: String) async throws -> [BrewProfile] {
    [BrewProfile(id: "light", title: "Claro")]
  }
  func schedules(deviceID: String) async throws -> [BrewSchedule] { [] }
  func importProfile(deviceID: String, link: String) async throws {}
  func shareProfile(deviceID: String, profileID: String) async throws -> URL {
    URL(string: "https://brew.fellowproducts.com/profile/test")!
  }
  func createSchedule(deviceID: String, draft: ScheduleDraft) async throws { scheduleWrites += 1 }
  func setScheduleEnabled(deviceID: String, scheduleID: String, enabled: Bool) async throws {
    scheduleWrites += 1
  }
  func deleteSchedule(deviceID: String, scheduleID: String) async throws { scheduleWrites += 1 }
  func startInstantBrew(deviceID: String) async throws {
    startCount += 1
    if startThrows { throw AidenError.uncertainResult }
  }
}

final class TestDateClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date = Date(timeIntervalSince1970: 1000)
  var now: Date { lock.withLock { date } }
  func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}

actor ControlledSleeper {
  private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]
  private var canceled: Set<UUID> = []
  var pendingCount: Int { continuations.count }
  func sleep(_ duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        if canceled.remove(id) != nil || Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          continuations[id] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }
  private func cancel(_ id: UUID) {
    if let continuation = continuations.removeValue(forKey: id) {
      continuation.resume(throwing: CancellationError())
    } else {
      canceled.insert(id)
    }
  }
  func advance() {
    let pending = continuations
    continuations.removeAll()
    for continuation in pending.values { continuation.resume() }
  }
}
