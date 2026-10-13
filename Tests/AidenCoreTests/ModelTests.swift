import Foundation
import Testing

@testable import AidenCore

@Test func firmwareGateUsesNumericVersionAndFailsClosed() {
  #expect(Brewer(id: "1", firmwareVersion: "1.5.16").supportsInstantBrew)
  #expect(Brewer(id: "1", firmwareVersion: "1.10.0").supportsInstantBrew)
  #expect(!Brewer(id: "1", firmwareVersion: "1.5.15").supportsInstantBrew)
  #expect(!Brewer(id: "1", firmwareVersion: "1.5.16-beta").supportsInstantBrew)
  #expect(!Brewer(id: "1").supportsInstantBrew)
}

@Test func instantBrewRequiresEveryKnownSafetyCondition() {
  var brewer = Brewer(
    id: "1", firmwareVersion: "1.5.16", isConnected: true, phase: .idle,
    missingWater: false, lidClosed: true, carafePresent: true,
    batchBrewBasketPresent: true, cleaning: false, rinsing: false, hasError: false)
  #expect(brewer.canStartInstantBrew)
  brewer.cleaning = nil
  #expect(!brewer.canStartInstantBrew)
  brewer.cleaning = false
  brewer.phase = .unknown
  #expect(!brewer.canStartInstantBrew)
}

@Test func scheduleValidatesDaysTimeVolumeAndProfile() throws {
  let valid = ScheduleDraft(
    days: [true, false, false, false, false, false, false], secondFromStartOfTheDay: 7 * 3600,
    amountOfWater: 150, profileId: "plocal12")
  try valid.validate()
  let encoded =
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as! [String: Any]
  #expect((encoded["days"] as? [Bool])?.first == true)
  var bad = valid
  bad.days = []
  #expect(throws: AidenError.invalidSchedule) { try bad.validate() }
  bad = valid
  bad.days = Array(repeating: false, count: 7)
  #expect(throws: AidenError.invalidSchedule) { try bad.validate() }
  bad = valid
  bad.amountOfWater = 149
  #expect(throws: AidenError.invalidSchedule) { try bad.validate() }
  bad = valid
  bad.secondFromStartOfTheDay = 86400
  #expect(throws: AidenError.invalidSchedule) { try bad.validate() }
  bad = valid
  bad.profileId = "../another"
  #expect(throws: AidenError.invalidSchedule) { try bad.validate() }
}
