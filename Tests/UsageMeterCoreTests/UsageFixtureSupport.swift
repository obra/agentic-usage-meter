import Foundation
import Testing

func usageFixture(named name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        )
    )
    return try Data(contentsOf: url)
}
