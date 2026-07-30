import Foundation

public struct HTTPResponse: Equatable, Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(
        data: Data,
        statusCode: Int,
        headers: [String: String]
    ) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [:]) { result, element in
            result[element.key.lowercased()] = element.value
        }
    }

    public func header(named name: String) -> String? {
        headers[name.lowercased()]
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public enum HTTPTransportError: Error, Equatable {
    case nonHTTPResponse
}

public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw HTTPTransportError.nonHTTPResponse
        }

        let headers = response.allHeaderFields.reduce(
            into: [String: String]()
        ) { result, element in
            guard let name = element.key as? String else {
                return
            }
            result[name] = String(describing: element.value)
        }

        return HTTPResponse(
            data: data,
            statusCode: response.statusCode,
            headers: headers
        )
    }
}

extension HTTPResponse {
    func retryDate(relativeTo now: Date) -> Date? {
        guard let value = header(named: "Retry-After") else {
            return nil
        }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}
