import Foundation

/// Lossless fields preserve the profile payload, while writes use an explicit schema allowlist.
enum JSONValue: Codable, Sendable, Equatable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let value = try? c.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? c.decode(String.self) {
      self = .string(value)
    } else if let value = try? c.decode(Double.self) {
      self = .number(value)
    } else if let value = try? c.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      self = .array(try c.decode([JSONValue].self))
    }
  }
  func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    }
  }
  var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
  var string: String? { if case .string(let v) = self { v } else { nil } }
  var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
  var number: Double? { if case .number(let v) = self { v } else { nil } }
  var int: Int? {
    guard let v = number, v.isFinite, v.rounded() == v, v >= Double(Int.min), v < Double(Int.max)
    else { return nil }
    return Int(v)
  }
  var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
}

struct BrewerPayload: Decodable, Sendable {
  let fields: [String: JSONValue]
  init(from decoder: any Decoder) throws {
    fields = try decoder.singleValueContainer().decode([String: JSONValue].self)
  }
  func brewer(fallbackID: String? = nil, previous: Brewer? = nil) throws -> Brewer {
    guard let id = fields["id"]?.string ?? fallbackID, !id.isEmpty else {
      throw AidenError.invalidResponse
    }
    let state = fields["state"]
    let stateObject = state?.object
    let phase: BrewPhase
    let hasError: Bool?
    if state == .null {
      phase = .idle
      hasError = false
    } else if let state {
      hasError = stateObject.map { $0["error"] != nil && $0["error"] != .null }
      switch state.object?["value"]?.string {
      case "b": phase = .bloom
      case "d": phase = .finishing
      case "pa": phase = .paused
      case .some(let value)
      where value.range(of: "^p([1-9]|10)$", options: .regularExpression) != nil: phase = .pulse
      default: phase = .unknown
      }
    } else {
      phase = fields["brewing"]?.bool.map { $0 ? .brewing : .idle } ?? .unknown
      hasError = nil
    }
    let topWater = fields["missingWater"]?.bool
    let nestedWater = stateObject?["missing_water"]?.bool
    let missingWater = (topWater == true || nestedWater == true) ? true : topWater ?? nestedWater
    return Brewer(
      id: id, name: fields["displayName"]?.string ?? previous?.name ?? "Aiden",
      firmwareVersion: fields["firmwareVersion"]?.string ?? previous?.firmwareVersion,
      timezone: fields["timezone"]?.string ?? previous?.timezone,
      isConnected: fields["isConnected"]?.bool, phase: phase, missingWater: missingWater,
      lidClosed: fields["lidClosed"]?.bool, carafePresent: fields["carafePresent"]?.bool,
      singleBrewBasketPresent: fields["singleBrewBasketPresent"]?.bool,
      batchBrewBasketPresent: fields["batchBrewBasketPresent"]?.bool,
      cleaning: fields["cleaning"]?.bool, rinsing: fields["rinsing"]?.bool, hasError: hasError,
      instantProfileID: fields["ibSelectedProfileId"]?.string,
      instantWaterQuantity: fields["ibWaterQuantity"]?.int,
      currentProfileID: fields["brewingProfileId"]?.string)
  }
}
