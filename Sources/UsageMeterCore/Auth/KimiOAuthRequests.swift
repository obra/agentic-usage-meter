import Foundation

public struct KimiDeviceInfo: Equatable, Sendable {
    public let name: String
    public let model: String
    public let osVersion: String
    public let id: String
    public let clientVersion: String

    public init(
        name: String,
        model: String,
        osVersion: String,
        id: String,
        clientVersion: String
    ) {
        self.name = name
        self.model = model
        self.osVersion = osVersion
        self.id = id
        self.clientVersion = clientVersion
    }
}

public enum KimiOAuthRequests {
    public static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"

    private static let authorizationEndpoint = URL(
        string: "https://auth.kimi.com/api/oauth/device_authorization"
    )!
    private static let tokenEndpoint = URL(
        string: "https://auth.kimi.com/api/oauth/token"
    )!

    public static func deviceAuthorizationRequest(
        device: KimiDeviceInfo
    ) throws -> URLRequest {
        try request(
            url: authorizationEndpoint,
            form: [
                URLQueryItem(name: "client_id", value: clientID)
            ],
            device: device
        )
    }

    public static func deviceTokenRequest(
        deviceCode: String,
        device: KimiDeviceInfo
    ) throws -> URLRequest {
        try request(
            url: tokenEndpoint,
            form: [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "device_code", value: deviceCode),
                URLQueryItem(
                    name: "grant_type",
                    value: "urn:ietf:params:oauth:grant-type:device_code"
                )
            ],
            device: device
        )
    }

    public static func refreshRequest(
        refreshToken: String,
        device: KimiDeviceInfo
    ) throws -> URLRequest {
        try request(
            url: tokenEndpoint,
            form: [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: refreshToken)
            ],
            device: device
        )
    }

    private static func request(
        url: URL,
        form: [URLQueryItem],
        device: KimiDeviceInfo
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try oauthFormData(form)
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("kimi_cli", forHTTPHeaderField: "X-Msh-Platform")
        request.setValue(
            asciiHeader(device.clientVersion),
            forHTTPHeaderField: "X-Msh-Version"
        )
        request.setValue(
            asciiHeader(device.name),
            forHTTPHeaderField: "X-Msh-Device-Name"
        )
        request.setValue(
            asciiHeader(device.model),
            forHTTPHeaderField: "X-Msh-Device-Model"
        )
        request.setValue(
            asciiHeader(device.osVersion),
            forHTTPHeaderField: "X-Msh-Os-Version"
        )
        request.setValue(
            asciiHeader(device.id),
            forHTTPHeaderField: "X-Msh-Device-Id"
        )
        return request
    }

    private static func asciiHeader(_ value: String) -> String {
        let sanitized = String(
            value.unicodeScalars.filter {
                $0.isASCII && $0.value >= 32 && $0.value != 127
            }
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "unknown" : sanitized
    }
}
