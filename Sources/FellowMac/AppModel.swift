import AidenCore
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var isConnected = false
  @Published private(set) var isDemo = false
  @Published private(set) var devices: [Brewer] = []
  @Published private(set) var selectedDeviceID: String?
  @Published private(set) var snapshot: Brewer?
  @Published private(set) var profiles: [BrewProfile] = []
  @Published private(set) var schedules: [BrewSchedule] = []
  @Published private(set) var lastFetchedAt: Date?
  @Published private(set) var isStale = false
  @Published private(set) var isLoading = false
  @Published private(set) var isRefreshing = false
  @Published private(set) var isMutating = false
  @Published var experimentalBrewEnabled = false
  @Published var showBrewConfirmation = false
  @Published var errorMessage: String?
  @Published var notice: String?
  @Published private(set) var demoScenario: DemoScenario = .idle
  @Published private(set) var pendingBrewDeviceIDs: Set<String> = []
  @Published private(set) var reconciledBrewDeviceIDs: Set<String> = []

  private let productionService: any AidenService
  private var service: any AidenService
  private let demoService = DemoService()
  private let pollingEnabled: Bool
  private let now: @Sendable () -> Date
  private let sleep: @Sendable (Duration) async throws -> Void
  @Published private var generation = UUID()
  var actionContextID: UUID { generation }
  private var refreshFlight: UUID?
  private var pollTask: Task<Void, Never>?
  private var demoTransitionTask: Task<Void, Never>?
  private var retryAt: Date?

  init(
    service: any AidenService, pollingEnabled: Bool = true,
    now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.service = service
    self.productionService = service
    self.pollingEnabled = pollingEnabled
    self.now = now
    self.sleep = sleep
  }

  var statusLabel: String {
    if isDemo && demoScenario == .connecting { return "Conectando" }
    guard let snapshot else { return "Selecione sua Aiden" }
    if snapshot.isConnected == false { return "Sem conexão" }
    return snapshot.phase.label
  }
  var isBrewing: Bool {
    guard let phase = snapshot?.phase else { return false }
    return [.bloom, .pulse, .finishing, .brewing].contains(phase)
  }
  var canOfferBrew: Bool {
    experimentalBrewEnabled && snapshot?.canStartInstantBrew == true && !isStale && !isMutating
      && !isRefreshing && !brewPending
  }
  var brewPending: Bool { selectedDeviceID.map { pendingBrewDeviceIDs.contains($0) } ?? false }
  var canAcknowledgeBrew: Bool {
    selectedDeviceID.map { reconciledBrewDeviceIDs.contains($0) } == true && !isStale
      && !isRefreshing && !isMutating
  }
  var canManageSchedules: Bool {
    guard let timezone = snapshot?.timezone, TimeZone(identifier: timezone) != nil else {
      return false
    }
    return isConnected && selectedDeviceID != nil && !isMutating
  }
  var instantProfileName: String {
    guard let id = snapshot?.instantProfileID else { return "Perfil indisponível" }
    return profiles.first(where: { $0.id == id })?.title ?? "Perfil configurado na Aiden"
  }

  func restore() async {
    guard !isConnected && !isLoading else { return }
    let token = generation
    isLoading = true
    defer { if generation == token { isLoading = false } }
    do {
      let restored = try await service.restoreSession()
      guard generation == token else { return }
      if restored {
        isConnected = true
        isLoading = false
        await loadDevices(token: token)
        resumePolling()
      }
    } catch { if generation == token { present(error) } }
  }

  func login(email: String, password: String) async {
    guard !isLoading else { return }
    resetVisibleState()
    isDemo = false
    service = productionService
    let token = generation
    isLoading = true
    defer { if generation == token { isLoading = false } }
    do {
      try await service.login(
        email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password,
        timezone: TimeZone.current.identifier)
      guard generation == token else { return }
      isConnected = true
      isLoading = false
      await loadDevices(token: token)
      resumePolling()
    } catch { if generation == token { present(error) } }
  }

  func logout() async {
    let previousService = service
    resetVisibleState()
    service = productionService
    isDemo = false
    let token = generation
    do { try await previousService.logout() } catch { if generation == token { present(error) } }
  }

  func enterDemo() async {
    guard !isLoading, !isMutating else { return }
    resetVisibleState()
    service = demoService
    isDemo = true
    isConnected = true
    demoScenario = .idle
    await demoService.setScenario(.idle)
    await loadDevices(token: generation)
    resumePolling()
  }

  func setDemoScenario(_ scenario: DemoScenario) async {
    guard isDemo, !isMutating else { return }
    demoTransitionTask?.cancel()
    demoTransitionTask = nil
    pausePolling()
    generation = UUID()
    refreshFlight = nil
    isRefreshing = false
    isLoading = false
    isStale = false
    errorMessage = nil
    notice = nil
    showBrewConfirmation = false
    demoScenario = scenario
    if scenario == .cloudError || scenario == .stale {
      if snapshot == nil {
        await demoService.setScenario(.idle)
        await loadDevices(token: generation)
        guard isDemo, demoScenario == scenario else { return }
      }
      await demoService.setScenario(scenario)
      await refresh()
      guard isDemo, demoScenario == scenario else { return }
      if scenario == .stale {
        errorMessage = nil
        notice = "Dados antigos simulados. O último estado foi preservado."
      }
      resumePolling()
      return
    }
    snapshot = nil
    profiles = []
    schedules = []
    devices = []
    selectedDeviceID = nil
    lastFetchedAt = nil
    if scenario == .connecting {
      isLoading = true
      let token = generation
      let sleep = sleep
      let transition = Task { [weak self] in
        do { try await sleep(.milliseconds(1500)) } catch { return }
        guard let self, self.generation == token, self.isDemo else { return }
        await self.setDemoScenario(.idle)
      }
      demoTransitionTask = transition
      await transition.value
      return
    }
    await demoService.setScenario(scenario)
    await loadDevices(token: generation)
    resumePolling()
  }

  private func loadDevices(token: UUID) async {
    guard !isRefreshing else { return }
    let flight = UUID()
    refreshFlight = flight
    isRefreshing = true
    defer {
      if refreshFlight == flight {
        isRefreshing = false
        refreshFlight = nil
      }
    }
    do {
      let fetched = try await service.devices()
      guard generation == token else { return }
      devices = fetched
      if fetched.count == 1 {
        isRefreshing = false
        refreshFlight = nil
        await selectDevice(fetched[0].id)
      } else {
        selectedDeviceID = nil
        snapshot = nil
        lastFetchedAt = nil
      }
    } catch { if generation == token { present(error) } }
  }

  func selectDevice(_ id: String) async {
    guard devices.contains(where: { $0.id == id }), !isMutating else { return }
    generation = UUID()
    refreshFlight = nil
    isRefreshing = false
    snapshot = nil
    profiles = []
    schedules = []
    lastFetchedAt = nil
    errorMessage = nil
    notice = nil
    isStale = false
    showBrewConfirmation = false
    selectedDeviceID = id
    await refresh()
  }

  func refresh(manual: Bool = false) async {
    guard isConnected, !isLoading, !isRefreshing, !isMutating else { return }
    if let retryAt, retryAt > now() { return }
    guard let id = selectedDeviceID else {
      await loadDevices(token: generation)
      return
    }
    let token = generation
    let flight = UUID()
    refreshFlight = flight
    isRefreshing = true
    defer {
      if refreshFlight == flight {
        isRefreshing = false
        refreshFlight = nil
      }
    }
    do {
      let fetched = try await service.device(id: id)
      guard generation == token, selectedDeviceID == id, fetched.id == id else { return }
      snapshot = fetched
      lastFetchedAt = now()
      isStale = false
      errorMessage = nil
      if isBrewing {
        pendingBrewDeviceIDs.remove(id)
        reconciledBrewDeviceIDs.remove(id)
      } else if manual, pendingBrewDeviceIDs.contains(id) {
        reconciledBrewDeviceIDs.insert(id)
      }
      let fetchedProfiles = try await service.profiles(deviceID: id)
      guard generation == token else { return }
      profiles = fetchedProfiles
      let fetchedSchedules = try await service.schedules(deviceID: id)
      guard generation == token else { return }
      schedules = fetchedSchedules
    } catch {
      if generation == token {
        isStale = true
        present(error)
      }
    }
  }

  func prepareBrewConfirmation() {
    guard canOfferBrew else { return }
    showBrewConfirmation = true
  }

  func confirmBrew() async {
    guard showBrewConfirmation, canOfferBrew, let id = selectedDeviceID else { return }
    showBrewConfirmation = false
    pendingBrewDeviceIDs.insert(id)
    reconciledBrewDeviceIDs.remove(id)
    await mutate { try await $0.startInstantBrew(deviceID: id) }
  }

  func acknowledgeBrew() {
    guard canAcknowledgeBrew, let id = selectedDeviceID else { return }
    pendingBrewDeviceIDs.remove(id)
    reconciledBrewDeviceIDs.remove(id)
    notice = "Cafeteira conferida. Um novo envio exige outra confirmação."
  }

  @discardableResult
  func importProfile(link: String, expectedDeviceID: String? = nil, expectedContextID: UUID? = nil)
    async -> Bool
  {
    guard validContext(deviceID: expectedDeviceID, contextID: expectedContextID),
      let id = selectedDeviceID
    else { return false }
    return await mutate { try await $0.importProfile(deviceID: id, link: link) }
  }

  func shareProfile(
    _ profile: BrewProfile, expectedDeviceID: String? = nil, expectedContextID: UUID? = nil
  ) async -> URL? {
    guard validContext(deviceID: expectedDeviceID, contextID: expectedContextID),
      let id = selectedDeviceID, profiles.contains(where: { $0.id == profile.id }), !isMutating,
      !isRefreshing
    else { return nil }
    let token = generation
    isMutating = true
    defer { if generation == token { isMutating = false } }
    do {
      let url = try await service.shareProfile(deviceID: id, profileID: profile.id)
      return generation == token ? url : nil
    } catch {
      if generation == token { present(error) }
      return nil
    }
  }

  @discardableResult
  func createSchedule(
    _ draft: ScheduleDraft, expectedDeviceID: String? = nil, expectedContextID: UUID? = nil
  ) async -> Bool {
    guard validContext(deviceID: expectedDeviceID, contextID: expectedContextID),
      canManageSchedules, !isRefreshing, let id = selectedDeviceID
    else { return false }
    do { try draft.validate() } catch {
      present(error)
      return false
    }
    return await mutate { try await $0.createSchedule(deviceID: id, draft: draft) }
  }

  func toggleSchedule(
    _ schedule: BrewSchedule, expectedDeviceID: String? = nil, expectedContextID: UUID? = nil
  ) async {
    guard validContext(deviceID: expectedDeviceID, contextID: expectedContextID),
      canManageSchedules, let id = selectedDeviceID
    else { return }
    await mutate {
      try await $0.setScheduleEnabled(
        deviceID: id, scheduleID: schedule.id, enabled: !schedule.enabled)
    }
  }

  func deleteSchedule(
    _ schedule: BrewSchedule, expectedDeviceID: String? = nil, expectedContextID: UUID? = nil
  ) async {
    guard validContext(deviceID: expectedDeviceID, contextID: expectedContextID),
      canManageSchedules, let id = selectedDeviceID
    else { return }
    await mutate { try await $0.deleteSchedule(deviceID: id, scheduleID: schedule.id) }
  }

  private func validContext(deviceID: String?, contextID: UUID?) -> Bool {
    (deviceID == nil || deviceID == selectedDeviceID)
      && (contextID == nil || contextID == generation)
  }

  @discardableResult
  private func mutate(_ action: @Sendable (any AidenService) async throws -> Void) async -> Bool {
    guard !isMutating, !isRefreshing else { return false }
    let token = generation
    isMutating = true
    do {
      try await action(service)
      guard generation == token else { return false }
      notice =
        isDemo
        ? "Alteração simulada na demonstração." : "Comando aceito pela nuvem. Confira a cafeteira."
      isMutating = false
      await refresh()
      return true
    } catch {
      if generation == token {
        isMutating = false
        isStale = true
        present(error)
      }
      return false
    }
  }

  func pausePolling() {
    pollTask?.cancel()
    pollTask = nil
  }
  func resumePolling() {
    pausePolling()
    guard pollingEnabled, isConnected, !isLoading else { return }
    let sleep = sleep
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await sleep(.seconds(60)) } catch { return }
        guard let self, !Task.isCancelled else { return }
        await self.refresh()
      }
    }
  }

  private func resetVisibleState() {
    demoTransitionTask?.cancel()
    demoTransitionTask = nil
    pausePolling()
    generation = UUID()
    refreshFlight = nil
    isConnected = false
    isLoading = false
    isRefreshing = false
    isMutating = false
    devices = []
    selectedDeviceID = nil
    snapshot = nil
    profiles = []
    schedules = []
    lastFetchedAt = nil
    isStale = false
    errorMessage = nil
    notice = nil
    retryAt = nil
    showBrewConfirmation = false
    experimentalBrewEnabled = false
    pendingBrewDeviceIDs = []
    reconciledBrewDeviceIDs = []
  }

  private func present(_ error: Error) {
    let safe = error as? AidenError ?? .unavailable
    errorMessage = safe.localizedDescription
    if case .rateLimited(let seconds) = safe {
      retryAt = now().addingTimeInterval(Double(max(1, seconds)))
    }
  }
}

enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
  case idle, brewing, offline, noDevices, connecting, cloudError, stale
  var id: String { rawValue }
  var label: String {
    switch self {
    case .idle: "Pronta"
    case .brewing: "Em preparo"
    case .offline: "Sem conexão"
    case .noDevices: "Sem aparelho"
    case .connecting: "Conectando"
    case .cloudError: "Falha da nuvem"
    case .stale: "Dados antigos"
    }
  }
}
