import Foundation

public struct SuperGrokUsageDecoder:
    Sendable
{
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let frames = dataFrames(in: data)
        guard !frames.isEmpty else {
            throw ProviderClientError
                .unsupportedResponse
        }

        var scan = ProtobufScan()
        var order = 0
        for frame in frames {
            scanProtobuf(
                frame,
                path: [],
                depth: 0,
                order: &order,
                scan: &scan
            )
        }

        let usageCandidates =
            scan.fixed32Fields
            .filter {
                $0.path.last == 1
                    && (0...100).contains(
                        $0.value
                    )
            }
            .sorted {
                if $0.path.count
                    != $1.path.count
                {
                    return $0.path.count
                        < $1.path.count
                }
                return $0.order < $1.order
            }
        let observedPath =
            usageCandidates.filter {
                $0.path == [1, 1]
            }
        guard
            let usedPercent =
                (observedPath.isEmpty
                ? usageCandidates
                : observedPath).first?
                .value,
            let resetAt = resetDate(
                in: scan,
                fetchedAt: fetchedAt
            ),
            let weekly = UsageWindow(
                id: "supergrok-weekly",
                kind: .weekly,
                duration: 7 * 24 * 60 * 60,
                resetAt: resetAt,
                consumedFraction:
                    usedPercent / 100
            )
        else {
            throw ProviderClientError
                .unsupportedResponse
        }

        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: [weekly]
        )
    }

    private func resetDate(
        in scan: ProtobufScan,
        fetchedAt: Date
    ) -> Date? {
        let candidates =
            scan.varintFields.compactMap {
                field -> (
                    path: [Int],
                    date: Date
                )?
                in
                guard
                    (1_700_000_000...2_100_000_000)
                        .contains(field.value)
                else {
                    return nil
                }
                let date = Date(
                    timeIntervalSince1970:
                        TimeInterval(field.value)
                )
                guard date > fetchedAt else {
                    return nil
                }
                return (field.path, date)
            }
        let observedPath =
            candidates
            .filter { $0.path == [1, 5, 1] }
            .map(\.date)
        return
            (observedPath.isEmpty
            ? candidates.map(\.date)
            : observedPath).min()
    }

    private func dataFrames(
        in data: Data
    ) -> [Data] {
        var frames: [Data] = []
        var index = 0

        while index + 5 <= data.count {
            let flags = data[index]
            let length =
                Int(data[index + 1]) << 24
                | Int(data[index + 2]) << 16
                | Int(data[index + 3]) << 8
                | Int(data[index + 4])
            let start = index + 5
            let end = start + length
            guard end <= data.count else {
                break
            }
            if flags & 0x80 == 0 {
                frames.append(
                    Data(data[start..<end])
                )
            }
            index = end
        }
        return frames
    }

    private func scanProtobuf(
        _ data: Data,
        path: [Int],
        depth: Int,
        order: inout Int,
        scan: inout ProtobufScan
    ) {
        var index = 0
        while index < data.count {
            let fieldStart = index
            guard
                let key = readVarint(
                    data,
                    index: &index
                ),
                key != 0
            else {
                index = min(
                    fieldStart + 1,
                    data.count
                )
                continue
            }

            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x07)
            let fieldPath =
                path + [fieldNumber]

            switch wireType {
            case 0:
                guard
                    let value = readVarint(
                        data,
                        index: &index
                    )
                else {
                    index = min(
                        fieldStart + 1,
                        data.count
                    )
                    continue
                }
                scan.varintFields.append(
                    .init(
                        path: fieldPath,
                        value: value
                    )
                )
            case 1:
                guard index + 8 <= data.count
                else {
                    return
                }
                index += 8
            case 2:
                guard
                    let rawLength = readVarint(
                        data,
                        index: &index
                    ),
                    rawLength
                        <= UInt64(data.count - index)
                else {
                    index = min(
                        fieldStart + 1,
                        data.count
                    )
                    continue
                }
                let length = Int(rawLength)
                let start = index
                let end = start + length
                if depth < 4 {
                    scanProtobuf(
                        Data(data[start..<end]),
                        path: fieldPath,
                        depth: depth + 1,
                        order: &order,
                        scan: &scan
                    )
                }
                index = end
            case 5:
                guard index + 4 <= data.count
                else {
                    return
                }
                let bits =
                    UInt32(data[index])
                    | UInt32(data[index + 1])
                    << 8
                    | UInt32(data[index + 2])
                    << 16
                    | UInt32(data[index + 3])
                    << 24
                index += 4
                let value = Double(
                    Float(bitPattern: bits)
                )
                if value.isFinite {
                    scan.fixed32Fields
                        .append(
                            .init(
                                path: fieldPath,
                                value: value,
                                order: order
                            )
                        )
                    order += 1
                }
            default:
                index = min(
                    fieldStart + 1,
                    data.count
                )
            }
        }
    }

    private func readVarint(
        _ data: Data,
        index: inout Int
    ) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.count,
            shift < 64
        {
            let byte = data[index]
            index += 1
            value |=
                UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return value
            }
            shift += 7
        }
        return nil
    }
}

private struct ProtobufScan {
    struct VarintField {
        let path: [Int]
        let value: UInt64
    }

    struct Fixed32Field {
        let path: [Int]
        let value: Double
        let order: Int
    }

    var varintFields: [VarintField] = []
    var fixed32Fields: [Fixed32Field] = []
}
