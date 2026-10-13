import Foundation

public protocol AidenService: Sendable {
  func restoreSession() async throws -> Bool
  func login(email: String, password: String, timezone: String) async throws
  func logout() async throws
  func devices() async throws -> [Brewer]
  func device(id: String) async throws -> Brewer
  func profiles(deviceID: String) async throws -> [BrewProfile]
  func schedules(deviceID: String) async throws -> [BrewSchedule]
  func importProfile(deviceID: String, link: String) async throws
  func shareProfile(deviceID: String, profileID: String) async throws -> URL
  func createSchedule(deviceID: String, draft: ScheduleDraft) async throws
  func setScheduleEnabled(deviceID: String, scheduleID: String, enabled: Bool) async throws
  func deleteSchedule(deviceID: String, scheduleID: String) async throws
  func startInstantBrew(deviceID: String) async throws
}
