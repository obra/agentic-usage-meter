import Foundation

enum OpenCodeDashboardHTML {
    static func normalized(
        _ data: Data
    ) throws -> String {
        guard
            var text = String(
                data: data,
                encoding: .utf8
            )
        else {
            throw ProviderClientError
                .unsupportedResponse
        }
        let replacements = [
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&#x27;", "'"),
            ("&#39;", "'"),
            ("&amp;", "&"),
            (#"\""#, "\""),
            (#"\u0022"#, "\""),
        ]
        for (encoded, decoded) in replacements {
            text = text.replacingOccurrences(
                of: encoded,
                with: decoded
            )
        }
        return text
    }

    static func objectBody(
        named fieldName: String,
        in text: String
    ) -> String? {
        let escaped =
            NSRegularExpression
            .escapedPattern(for: fieldName)
        let pattern =
            #"["']?\#(escaped)["']?\s*:\s*(?:\$R\[\d+\]\s*=\s*)?\{(?<body>[^{}]*)\}"#
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [
                    .dotMatchesLineSeparators
                ]
            ),
            let match = expression.firstMatch(
                in: text,
                range: NSRange(
                    text.startIndex...,
                    in: text
                )
            ),
            let range = Range(
                match.range(
                    withName: "body"
                ),
                in: text
            )
        else {
            return nil
        }
        return String(text[range])
    }

    static func number(
        named fieldName: String,
        in text: String
    ) -> Double? {
        let escaped =
            NSRegularExpression
            .escapedPattern(for: fieldName)
        let pattern =
            #"["']?\#(escaped)["']?\s*:\s*"?(-?\d+(?:\.\d+)?)"?"#
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern
            ),
            let match = expression.firstMatch(
                in: text,
                range: NSRange(
                    text.startIndex...,
                    in: text
                )
            ),
            let range = Range(
                match.range(at: 1),
                in: text
            )
        else {
            return nil
        }
        return Double(text[range])
    }

    static func string(
        named fieldName: String,
        in text: String
    ) -> String? {
        let escaped =
            NSRegularExpression
            .escapedPattern(for: fieldName)
        let pattern =
            #"["']?\#(escaped)["']?\s*:\s*["']([^"']+)["']"#
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern
            ),
            let match = expression.firstMatch(
                in: text,
                range: NSRange(
                    text.startIndex...,
                    in: text
                )
            ),
            let range = Range(
                match.range(at: 1),
                in: text
            )
        else {
            return nil
        }
        return String(text[range])
    }

    static func date(
        named fieldName: String,
        in text: String
    ) -> Date? {
        guard
            let value = string(
                named: fieldName,
                in: text
            )
        else {
            return nil
        }

        let fractional =
            ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractional.date(
            from: value
        ) {
            return date
        }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [
            .withInternetDateTime
        ]
        return internet.date(from: value)
    }
}
