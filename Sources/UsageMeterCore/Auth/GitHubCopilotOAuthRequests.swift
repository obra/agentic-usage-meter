import Foundation

public enum GitHubCopilotOAuthRequests {
    public static let clientID = "Ov23ctDVkRmgkPke0Mmm"

    private static let deviceAuthorizationEndpoint = URL(
        string: "https://github.com/login/device/code"
    )!
    private static let accessTokenEndpoint = URL(
        string: "https://github.com/login/oauth/access_token"
    )!

    public static func deviceAuthorizationRequest()
        throws -> URLRequest
    {
        try request(
            url: deviceAuthorizationEndpoint,
            form: [
                URLQueryItem(
                    name: "client_id",
                    value: clientID
                )
            ]
        )
    }

    public static func accessTokenRequest(
        deviceCode: String
    ) throws -> URLRequest {
        try request(
            url: accessTokenEndpoint,
            form: [
                URLQueryItem(
                    name: "client_id",
                    value: clientID
                ),
                URLQueryItem(
                    name: "device_code",
                    value: deviceCode
                ),
                URLQueryItem(
                    name: "grant_type",
                    value:
                        "urn:ietf:params:oauth:grant-type:device_code"
                ),
            ]
        )
    }

    private static func request(
        url: URL,
        form: [URLQueryItem]
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try oauthFormData(form)
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        return request
    }
}
