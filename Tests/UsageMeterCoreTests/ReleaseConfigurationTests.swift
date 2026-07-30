import Foundation
import Testing

@Suite
struct ReleaseConfigurationTests {
    @Test
    func applicationBundleDeclaresMenuBarReleaseContract() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(
                from: data,
                format: nil,
            ) as? [String: Any],
        )

        #expect(
            plist["CFBundleIdentifier"] as? String
                == "com.jesse.agentic-usage-meter",
        )
        #expect(
            plist["CFBundleName"] as? String
                == "Agentic Usage Meter",
        )
        #expect(plist["CFBundleExecutable"] as? String == "AgenticUsageMeter")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
    }
}
