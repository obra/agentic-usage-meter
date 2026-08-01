import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct SuperGrokUsageDecoderTests {
    @Test
    func weeklyUsedPercentAndResetBecomeAWeeklyWindow()
        throws
    {
        let accountID = UUID()
        let fetchedAt = Date(
            timeIntervalSince1970: 1_785_000_000
        )
        let resetAt = Date(
            timeIntervalSince1970: 1_785_600_000
        )
        var weekly = Data()
        weekly.append(fixed32Field(1, 42.5))
        weekly.append(
            lengthDelimitedField(
                5,
                varintField(
                    1,
                    UInt64(
                        resetAt.timeIntervalSince1970
                    )
                )
            )
        )
        let response = grpcWebFrame(
            lengthDelimitedField(1, weekly)
        )

        let snapshot = try SuperGrokUsageDecoder()
            .decode(
                response,
                accountID: accountID,
                fetchedAt: fetchedAt
            )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fetchedAt == fetchedAt)
        let window = try #require(
            snapshot.windows.only
        )
        #expect(window.id == "supergrok-weekly")
        #expect(window.kind == .weekly)
        #expect(window.duration == 7 * 24 * 60 * 60)
        #expect(window.resetAt == resetAt)
        #expect(
            abs(window.consumedFraction - 0.425)
                < 0.0001
        )
        #expect(snapshot.balances.isEmpty)
    }

    @Test
    func observedWeeklyPathWinsOverOtherFloatFields()
        throws
    {
        let resetEpoch: UInt64 = 1_785_600_000
        var weekly = Data()
        weekly.append(fixed32Field(1, 25))
        weekly.append(
            lengthDelimitedField(
                5,
                varintField(1, resetEpoch)
            )
        )
        var root = Data()
        root.append(fixed32Field(1, 99))
        root.append(
            lengthDelimitedField(1, weekly)
        )

        let snapshot = try SuperGrokUsageDecoder()
            .decode(
                grpcWebFrame(root),
                accountID: UUID(),
                fetchedAt: Date(
                    timeIntervalSince1970:
                        TimeInterval(resetEpoch - 1)
                )
            )

        #expect(
            snapshot.windows.only?
                .consumedFraction == 0.25
        )
    }

    @Test
    func responseWithoutUsageOrResetIsRejected() {
        #expect(
            throws:
                ProviderClientError
                .unsupportedResponse
        ) {
            _ = try SuperGrokUsageDecoder()
                .decode(
                    grpcWebFrame(Data()),
                    accountID: UUID(),
                    fetchedAt: Date()
                )
        }
    }
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}

private func encodeVarint(
    _ value: UInt64
) -> Data {
    var remaining = value
    var data = Data()
    while remaining >= 0x80 {
        data.append(
            UInt8(remaining & 0x7F) | 0x80
        )
        remaining >>= 7
    }
    data.append(UInt8(remaining))
    return data
}

private func varintField(
    _ fieldNumber: UInt8,
    _ value: UInt64
) -> Data {
    var data = Data(
        [(fieldNumber << 3) | 0]
    )
    data.append(encodeVarint(value))
    return data
}

private func lengthDelimitedField(
    _ fieldNumber: UInt8,
    _ payload: Data
) -> Data {
    var data = Data(
        [(fieldNumber << 3) | 2]
    )
    data.append(
        encodeVarint(UInt64(payload.count))
    )
    data.append(payload)
    return data
}

private func fixed32Field(
    _ fieldNumber: UInt8,
    _ value: Float
) -> Data {
    var data = Data(
        [(fieldNumber << 3) | 5]
    )
    let bits = value.bitPattern
    data.append(
        contentsOf: [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
        ]
    )
    return data
}

private func grpcWebFrame(
    _ payload: Data
) -> Data {
    var frame = Data([0])
    frame.append(
        contentsOf: [
            UInt8((payload.count >> 24) & 0xFF),
            UInt8((payload.count >> 16) & 0xFF),
            UInt8((payload.count >> 8) & 0xFF),
            UInt8(payload.count & 0xFF),
        ]
    )
    frame.append(payload)
    return frame
}
