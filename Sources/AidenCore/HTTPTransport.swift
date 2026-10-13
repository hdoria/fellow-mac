import Foundation

public struct HTTPResponse: Sendable {
  public let status: Int
  public let headers: [String: String]
  public let data: Data
  public init(status: Int, headers: [String: String] = [:], data: Data = Data()) {
    self.status = status
    self.headers = headers
    self.data = data
  }
}

public protocol HTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
  private let session: URLSession
  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    session = URLSession(
      configuration: configuration, delegate: DenyRedirects(), delegateQueue: nil)
  }
  public func send(_ request: URLRequest) async throws -> HTTPResponse {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, data.count <= 2_000_000 else {
      throw AidenError.invalidResponse
    }
    var headers: [String: String] = [:]
    for (key, value) in http.allHeaderFields {
      headers[String(describing: key).lowercased()] = String(describing: value)
    }
    return HTTPResponse(status: http.statusCode, headers: headers, data: data)
  }
}

/// Never forward an Authorization header to another location, even same-host redirects.
private final class DenyRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
