import Foundation
import UsageMeterCore

public extension KimiDeviceInfo {
    static func currentMac(accountID: UUID) -> KimiDeviceInfo {
        KimiDeviceInfo(
            name: Host.current().localizedName ?? "Mac",
            model: "macOS",
            osVersion:
                ProcessInfo.processInfo
                .operatingSystemVersionString,
            id: accountID.uuidString.lowercased(),
            clientVersion:
                Bundle.main.object(
                    forInfoDictionaryKey:
                        "CFBundleShortVersionString",
                ) as? String
                ?? "0.1.0",
        )
    }
}
