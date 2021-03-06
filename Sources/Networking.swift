import Foundation
import When

// MARK: - Mode

public enum NetworkingMode {
  case sync, async, limited(Int)
}

// MARK: - Mocks

public struct MockProvider<R: RequestConvertible> {
  let resolver: (R) -> Mock?
  let delay: TimeInterval

  public init(delay: TimeInterval = 0, resolver: @escaping (R) -> Mock?) {
    self.resolver = resolver
    self.delay = delay
  }
}

struct MockBehavior {
  let mock: Mock
  let delay: TimeInterval
}

// MARK: - Networking

public final class Networking<R: RequestConvertible>: NSObject, URLSessionDelegate {

  public var beforeEach: ((Request) -> Request)?
  public var preProcessRequest: ((URLRequest) -> URLRequest)?

  public var middleware: (Promise<Void>) -> Void = { promise in
    promise.resolve()
  }

  let sessionConfiguration: SessionConfiguration
  let mockProvider: MockProvider<R>?
  let queue: OperationQueue

  var customHeaders = [String: String]()
  var requestStorage = RequestStorage()
  var mode: NetworkingMode = .async

  weak var sessionDelegate: URLSessionDelegate?

  lazy var session: URLSession = { [unowned self] in
    let session = URLSession(
      configuration: self.sessionConfiguration.value,
      delegate: self.sessionDelegate ?? self,
      delegateQueue: nil)
    return session
  }()

  var requestHeaders: [String: String] {
    var headers = customHeaders
    headers["Accept-Language"] = Header.acceptLanguage
    let extraHeaders = R.headers

    extraHeaders.forEach { key, value in
      headers[key] = value
    }

    return headers
  }

  // MARK: - Initialization

  public init(mode: NetworkingMode = .async,
              mockProvider: MockProvider<R>? = nil,
              sessionConfiguration: SessionConfiguration = SessionConfiguration.default,
              sessionDelegate: URLSessionDelegate? = nil) {
    self.mockProvider = mockProvider
    self.sessionConfiguration = sessionConfiguration
    self.sessionDelegate = sessionDelegate
    queue = OperationQueue()
    super.init()
    reset(mode: mode)
  }

  public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    var disposition: URLSession.AuthChallengeDisposition = .performDefaultHandling
    var credential: URLCredential?

    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
      if let serverTrust = challenge.protectionSpace.serverTrust,
        let urlString = R.baseUrl?.urlString,
        let baseURL = URL(string: urlString) {
        if challenge.protectionSpace.host == baseURL.host {
          disposition = .useCredential
          credential = URLCredential(trust: serverTrust)
        } else {
          disposition = .cancelAuthenticationChallenge
        }
      }
    } else {
      if challenge.previousFailureCount > 0 {
        disposition = .rejectProtectionSpace
      } else {
        credential = session.configuration.urlCredentialStorage?.defaultCredential(
          for: challenge.protectionSpace)

        if credential != nil {
          disposition = .useCredential
        }
      }
    }

    completionHandler(disposition, credential)
  }

  public func resume() {
    queue.isSuspended = false
  }

  public func suspend() {
    queue.isSuspended = true
  }

  func reset(mode: NetworkingMode) {
    self.mode = mode

    switch mode {
    case .sync:
      queue.maxConcurrentOperationCount = 1
    case .async:
      queue.maxConcurrentOperationCount = -1
    case .limited(let count):
      queue.maxConcurrentOperationCount = count
    }
  }
}

// MARK: - Request

extension Networking {

  public func request(_ requestConvertible: R) -> NetworkPromise {
    var mockBehavior: MockBehavior?

    if let mockProvider = mockProvider, let mock = mockProvider.resolver(requestConvertible) {
      mockBehavior = MockBehavior(mock: mock, delay: mockProvider.delay)
    }

    return execute(requestConvertible.request, mockBehavior: mockBehavior)
  }

  public func cancelAllRequests() {
    queue.cancelAllOperations()
  }

  func execute(_ request: Request, mockBehavior: MockBehavior? = nil) -> NetworkPromise {
    let networkPromise = NetworkPromise()
    let beforePromise = Promise<Void>()

    beforePromise
      .then({
        return self.start(request, mockBehavior: mockBehavior)
      })
      .done({ response in
        networkPromise.resolve(response)
      })
      .fail({ error in
        networkPromise.reject(error)
      })

    middleware(beforePromise)

    return networkPromise
  }

  func start(_ request: Request, mockBehavior: MockBehavior? = nil) -> NetworkPromise {
    let networkPromise = NetworkPromise()
    var urlRequest: URLRequest

    do {
      let request = beforeEach?(request) ?? request
      urlRequest = try request.toUrlRequest(baseUrl: R.baseUrl, additionalHeaders: requestHeaders)
    } catch {
      networkPromise.reject(error)
      return networkPromise
    }

    if let preProcessRequest = preProcessRequest {
      urlRequest = preProcessRequest(urlRequest)
    }

    let operation = createOperation(
      networkPromise: networkPromise,
      urlRequest: urlRequest,
      mockBehavior: mockBehavior
    )

    let etagPromise = networkPromise.then { [weak self] result -> Response in
      self?.saveEtag(request: request, response: result.response)
      return result
    }

    let nextNetworkPromise = NetworkPromise()

    etagPromise
      .done({ value in
        if logger.enabled {
          logger.requestLogger.init(level: logger.level).log(request: request, urlRequest: value.request)
          logger.responseLogger.init(level: logger.level).log(response: value.response)
        }

        nextNetworkPromise.resolve(value)
      })
      .fail({ [weak self] error in
        if logger.enabled {
          logger.errorLogger.init(level: logger.level).log(error: error)
        }

        self?.handle(error: error, on: request)
        nextNetworkPromise.reject(error)
      })

    queue.addOperation(operation)

    return nextNetworkPromise
  }

  func createOperation(networkPromise: NetworkPromise, urlRequest: URLRequest,
                       mockBehavior: MockBehavior?) -> ConcurrentOperation {
    let operation: ConcurrentOperation

    if let mockBehavior = mockBehavior {
      operation = MockOperation(
        mock: mockBehavior.mock,
        urlRequest: urlRequest,
        delay: mockBehavior.delay
      )
    } else {
      operation = DataOperation(session: session, urlRequest: urlRequest)
    }

    let responseHandler = ResponseHandler(urlRequest: urlRequest, networkPromise: networkPromise)
    operation.handleResponse = responseHandler.handle(data:urlResponse:error:)
    networkPromise.operation = operation
    return operation
  }
}

// MARK: - Authentication

extension Networking {

  public func authenticate(username: String, password: String) {
    guard let header = Header.authentication(username: username, password: password) else {
      return
    }

    customHeaders["Authorization"] = header
  }

  public func authenticate(authorizationHeader: String) {
    customHeaders["Authorization"] = authorizationHeader
  }

  public func authenticate(bearerToken: String) {
    customHeaders["Authorization"] = "Bearer \(bearerToken)"
  }
}

// MARK: - Helpers

extension Networking {

  func saveEtag(request: Request, response: HTTPURLResponse) {
    guard let etag = response.allHeaderFields["ETag"] as? String else {
      return
    }

    let prefix = R.baseUrl?.urlString ?? ""

    EtagStorage().add(value: etag, forKey: request.etagKey(prefix: prefix))
  }

  func handle(error: Error, on request: Request) {
    guard request.storePolicy == StorePolicy.offline && (error as NSError).isOffline else {
      return
    }

    requestStorage.save(RequestCapsule(request: request))
  }
}

// MARK: - Replay

extension Networking {

  public func replay() -> NetworkPromise {
    let requests = requestStorage.requests.values
    let currentMode = mode

    reset(mode: .sync)

    let lastNetworkPromise = NetworkPromise()

    for (index, capsule) in requests.enumerated() {
      let isLast = index == requests.count - 1

      execute(capsule.request)
        .done({ value in
          guard isLast else { return }
          lastNetworkPromise.resolve(value)
        })
        .fail({ error in
          guard isLast else { return }
          lastNetworkPromise.reject(error)
        })
        .always({ [weak self] result in
          if isLast {
            self?.reset(mode: currentMode)
          }

          if let error = result.error, (error as NSError).isOffline {
            return
          }

          self?.requestStorage.remove(capsule)
        })
    }

    return lastNetworkPromise
  }
}
