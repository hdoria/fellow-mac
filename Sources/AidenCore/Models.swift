import Foundation

public struct SessionTokens: Codable, Sendable, Equatable {
  public let accessToken: String
  public let refreshToken: String
  public init(accessToken: String, refreshToken: String) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
  }
}

public protocol TokenStore: Sendable {
  func load() async throws -> SessionTokens?
  func save(_ tokens: SessionTokens) async throws
  func clear() async throws
}

public enum BrewPhase: String, Sendable, Codable {
  case idle, bloom, pulse, finishing, paused, brewing, unknown
  public var label: String {
    switch self {
    case .idle: "Pronta"
    case .bloom: "Pré-infusão"
    case .pulse: "Em preparo"
    case .finishing: "Finalizando"
    case .paused: "Pausada"
    case .brewing: "Em preparo"
    case .unknown: "Estado indisponível"
    }
  }
}

public struct Brewer: Identifiable, Sendable, Equatable {
  public var id: String
  public var name: String
  public var firmwareVersion: String?
  public var timezone: String?
  public var isConnected: Bool?
  public var phase: BrewPhase
  public var missingWater: Bool?
  public var lidClosed: Bool?
  public var carafePresent: Bool?
  public var singleBrewBasketPresent: Bool?
  public var batchBrewBasketPresent: Bool?
  public var cleaning: Bool?
  public var rinsing: Bool?
  public var hasError: Bool?
  /// Time reported by the machine, never substituted with the HTTP fetch time.
  public var telemetryAt: Date?
  public var instantProfileID: String?
  public var instantWaterQuantity: Int?
  public var currentProfileID: String?
  public init(
    id: String, name: String = "Aiden", firmwareVersion: String? = nil,
    timezone: String? = nil, isConnected: Bool? = nil, phase: BrewPhase = .unknown,
    missingWater: Bool? = nil, lidClosed: Bool? = nil, carafePresent: Bool? = nil,
    singleBrewBasketPresent: Bool? = nil, batchBrewBasketPresent: Bool? = nil,
    cleaning: Bool? = nil, rinsing: Bool? = nil, hasError: Bool? = nil,
    telemetryAt: Date? = nil, instantProfileID: String? = nil,
    instantWaterQuantity: Int? = nil, currentProfileID: String? = nil
  ) {
    self.id = id
    self.name = name
    self.firmwareVersion = firmwareVersion
    self.timezone = timezone
    self.isConnected = isConnected
    self.phase = phase
    self.missingWater = missingWater
    self.lidClosed = lidClosed
    self.carafePresent = carafePresent
    self.singleBrewBasketPresent = singleBrewBasketPresent
    self.batchBrewBasketPresent = batchBrewBasketPresent
    self.cleaning = cleaning
    self.rinsing = rinsing
    self.hasError = hasError
    self.telemetryAt = telemetryAt
    self.instantProfileID = instantProfileID
    self.instantWaterQuantity = instantWaterQuantity
    self.currentProfileID = currentProfileID
  }
  public var supportsInstantBrew: Bool {
    guard let version = firmwareVersion?.trimmingCharacters(in: .whitespaces),
      version.range(
        of: "^v?[0-9]+\\.[0-9]+\\.[0-9]+(?:\\+[A-Za-z0-9.-]+)?$", options: .regularExpression)
        != nil
    else { return false }
    let base = version.split(separator: "+")[0].replacingOccurrences(of: "v", with: "")
    let parts = base.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 3 else { return false }
    return parts.lexicographicallyPrecedes([1, 5, 16]) == false
  }
  public var canStartInstantBrew: Bool {
    supportsInstantBrew && isConnected == true && phase == .idle && hasError == false
      && missingWater == false && lidClosed == true && cleaning == false && rinsing == false
      && (singleBrewBasketPresent == true
        || (batchBrewBasketPresent == true && carafePresent == true))
  }
}

public struct BrewProfile: Identifiable, Sendable, Equatable {
  public let id: String
  public let title: String
  public let ratio: Double?
  public let bloomTemperature: Double?
  public let bloomDuration: Int?
  public init(
    id: String, title: String, ratio: Double? = nil,
    bloomTemperature: Double? = nil, bloomDuration: Int? = nil
  ) {
    self.id = id
    self.title = title
    self.ratio = ratio
    self.bloomTemperature = bloomTemperature
    self.bloomDuration = bloomDuration
  }
}

public struct BrewSchedule: Identifiable, Sendable, Equatable {
  public let id: String
  public let days: [Bool]
  public let secondFromStartOfTheDay: Int
  public let enabled: Bool
  public let amountOfWater: Int
  public let profileId: String
  public init(
    id: String, days: [Bool], secondFromStartOfTheDay: Int, enabled: Bool,
    amountOfWater: Int, profileId: String
  ) {
    self.id = id
    self.days = days
    self.secondFromStartOfTheDay = secondFromStartOfTheDay
    self.enabled = enabled
    self.amountOfWater = amountOfWater
    self.profileId = profileId
  }
}

public struct ScheduleDraft: Sendable, Codable, Equatable {
  /// Sunday through Saturday. The selected local time means coffee ready at.
  public var days: [Bool]
  public var secondFromStartOfTheDay: Int
  public var enabled: Bool
  public var amountOfWater: Int
  public var profileId: String
  public init(
    days: [Bool], secondFromStartOfTheDay: Int, enabled: Bool = true,
    amountOfWater: Int, profileId: String
  ) {
    self.days = days
    self.secondFromStartOfTheDay = secondFromStartOfTheDay
    self.enabled = enabled
    self.amountOfWater = amountOfWater
    self.profileId = profileId
  }
  public func validate() throws {
    guard days.count == 7, days.contains(true), (0..<86400).contains(secondFromStartOfTheDay),
      (150...1500).contains(amountOfWater),
      profileId.range(of: "^(p|plocal)[0-9]+$", options: .regularExpression) != nil
    else {
      throw AidenError.invalidSchedule
    }
  }
}

public enum AidenError: Error, LocalizedError, Sendable, Equatable {
  case authentication, sessionChanged, unavailable, invalidResponse, invalidLink, invalidSchedule
  case invalidProfile, unsupportedDevice, unsafeBrew, uncertainResult, storage
  case rateLimited(seconds: Int)
  public var errorDescription: String? {
    switch self {
    case .authentication: "Sua sessão expirou ou o login foi recusado. Conecte a conta novamente."
    case .sessionChanged: "A sessão mudou. Conecte a conta novamente."
    case .unavailable: "Não foi possível consultar a Fellow. Tente atualizar."
    case .invalidResponse: "A Fellow retornou dados incompatíveis."
    case .invalidLink: "Use um link de perfil Aiden da Fellow."
    case .invalidSchedule: "Confira os dias, horário, perfil e volume de 150 a 1500 ml."
    case .invalidProfile: "O perfil contém parâmetros incompatíveis."
    case .unsupportedDevice: "Este aparelho não é uma Aiden compatível."
    case .unsafeBrew: "O estado atual não permite iniciar. Atualize e confira a cafeteira."
    case .uncertainResult: "O resultado do comando é incerto. Atualize antes de decidir reenviar."
    case .storage:
      "Não foi possível acessar a sessão no Keychain. Desbloqueie o Mac e tente novamente."
    case .rateLimited(let seconds): "A Fellow limitou as consultas. Aguarde \(seconds) segundos."
    }
  }
}
