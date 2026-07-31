import Testing
@testable import UsageMeterCore

@Test
func developmentRefreshPolicyUsesOneMinuteIntervals() {
    #expect(RefreshPolicy.development.automaticInterval == 60)
    #expect(RefreshPolicy.development.minimumProviderInterval == 60)
}

@Test
func releaseRefreshPolicyUsesTenMinuteIntervals() {
    #expect(RefreshPolicy.release.automaticInterval == 600)
    #expect(RefreshPolicy.release.minimumProviderInterval == 600)
}
