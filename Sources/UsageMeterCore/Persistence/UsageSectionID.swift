public enum UsageSectionID:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable
{
    case short
    case daily
    case weekly
    case monthly
    case custom
    case extraCredits = "extra-credits"
}
