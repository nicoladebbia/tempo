@testable import Tempo
import Testing

@MainActor
struct SubscriptionServiceObservingTests {
    /// Regression: nothing ever called `startObserving()`, so a paying user
    /// looked free after relaunch and renewals/refunds were never picked up.
    @Test func startObservingMarksObservingAndIsIdempotent() async {
        let service = SubscriptionService()
        #expect(service.isObserving == false)
        await service.startObserving()
        #expect(service.isObserving == true)
        await service.startObserving() // second call must be a harmless no-op
        #expect(service.isObserving == true)
        // No StoreKit entitlement in the test host → stays free, never crashes.
        #expect(service.isPro == false)
    }
}
