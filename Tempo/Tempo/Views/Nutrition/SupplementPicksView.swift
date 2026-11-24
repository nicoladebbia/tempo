//
// SupplementPicksView.swift
// Tempo
//
// "Best <type>" picks for a supplement the user already owns — 2-3 curated,
// third-party-certified products (or an honestly-labeled AI fallback for an
// unusual supplement), plus nearby stores that might carry them. Reached from
// the supplement shelf / detail (embedded by the coordinator, not this view).
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice. Never invents a
// product or certification; the backend already guarantees that (see
// tempo-backend SupplementCuratedCatalog.swift) — this view just renders it
// honestly, including the `verified == false` disclosure.
//

import CoreLocation
import MapKit
import SwiftUI

// MARK: - SupplementPicksView

struct SupplementPicksView: View {
    let supplement: Supplement

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.openURL)
    private var openURL

    @State private var picks: SupplementPicksDTO?
    @State private var isLoading = true
    @State private var loadErrorMessage: String?

    @State private var nearbyState: NearbyState = .idle
    @State private var locationProvider = SupplementLocationProvider()

    private enum NearbyState {
        case idle
        case loading
        case denied
        case loaded([NearbyStoreResult])
        case failed
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Tide.s4) {
                if isLoading {
                    loadingState
                } else if let loadErrorMessage {
                    errorState(loadErrorMessage)
                } else if let picks {
                    content(for: picks)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s3)
            .padding(.bottom, Tide.s10)
        }
        .kitchenPage()
        .navigationTitle("Best \(supplement.kind.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPicks()
        }
    }

    // MARK: - Loading / error

    private var loadingState: some View {
        VStack(spacing: Tide.s3) {
            // The shape of the answer while it loads: two pick cards.
            VStack(spacing: Tide.s3) {
                ForEach(0 ..< 2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                        .fill(Tide.fill)
                        .frame(height: Tide.Kitchen.suggestion + Tide.s10)
                }
            }
            .shimmer()
            Text("Finding the best picks…")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finding the best picks")
    }

    private func errorState(_ message: String) -> some View {
        KitchenFailure(
            title: "Picks unavailable",
            message: message,
            retryTitle: "Try Again",
            retry: { Task { await loadPicks() } }
        )
    }

    // MARK: - Content

    private func content(for picks: SupplementPicksDTO) -> some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            if let lookFor = picks.lookFor, !lookFor.isEmpty {
                lookForCard(lookFor)
            }

            if !picks.verified {
                unverifiedBanner
            }

            if picks.picks.isEmpty {
                emptyPicksState
            } else {
                VStack(spacing: Tide.s3) {
                    ForEach(picks.picks, id: \.id) { pick in
                        pickCard(pick)
                    }
                }
            }

            nearbySection
        }
    }

    private func lookForCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text("What to look for").tideLabel()
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
    }

    private var unverifiedBanner: some View {
        KitchenNotice(
            systemImage: "sparkles",
            text: "AI suggestions, not verified. Double-check any certification claim yourself before buying."
        )
    }

    private var emptyPicksState: some View {
        KitchenEmpty(
            systemImage: "magnifyingglass",
            title: "No picks right now",
            message: "No suggestions available for this one right now. Try again later, or search for a third-party certified option yourself."
        )
    }

    private func pickCard(_ pick: SupplementPicksDTO.Pick) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(pick.brand).tideLabel(Tide.text3)
                Text(pick.product)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                if let form = pick.form, !form.isEmpty {
                    Text(form.capitalized)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }

            if !pick.certifications.isEmpty {
                HStack(spacing: Tide.s1) {
                    ForEach(pick.certifications, id: \.self) { certification in
                        certificationBadge(certification)
                    }
                }
            }

            Text(pick.why)
                .font(Tide.body)
                .foregroundStyle(Tide.text)

            if let price = pick.approxPricePerServingUSD {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    TideNumber(
                        String(format: "$%.2f", price),
                        unit: "/serving",
                        size: Tide.numeralS,
                        relativeTo: .headline
                    )
                    if let priceAsOf = pick.priceAsOf, let formatted = Self.formatPriceAsOf(priceAsOf) {
                        Text("approx. \(formatted)")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(priceLine(for: pick))
            }

            if !pick.buyLinks.isEmpty {
                HStack(spacing: Tide.s2) {
                    ForEach(pick.buyLinks, id: \.url) { link in
                        buyLinkButton(link)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
    }

    private func priceLine(for pick: SupplementPicksDTO.Pick) -> String {
        guard let price = pick.approxPricePerServingUSD else {
            return ""
        }
        let priceText = String(format: "~$%.2f/serving", price)
        guard let priceAsOf = pick.priceAsOf, let formatted = Self.formatPriceAsOf(priceAsOf) else {
            return priceText
        }
        return "\(priceText) (\(formatted))"
    }

    private func certificationBadge(_ text: String) -> some View {
        KitchenTag(text: text, tint: Tide.Kitchen.good)
    }

    private func buyLinkButton(_ link: SupplementPicksDTO.BuyLink) -> some View {
        Button {
            if let url = URL(string: link.url) {
                openURL(url)
            }
        } label: {
            Text(link.label)
                .font(Tide.bodyStrong)
        }
        .buttonStyle(.tideGlass)
    }

    // MARK: - Nearby

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Nearby stores").tideLabel()

            switch nearbyState {
            case .idle:
                Button {
                    Task { await loadNearby() }
                } label: {
                    Label("Find Nearby Stores", systemImage: "location")
                }
                .buttonStyle(.tideGlass)

            case .loading:
                VStack(spacing: Tide.s2) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                            .fill(Tide.fill)
                            .frame(height: Tide.Kitchen.tile)
                    }
                }
                .shimmer()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Searching nearby")

            case .denied:
                KitchenNotice(
                    systemImage: "location.slash",
                    text: "Location access is off, so we can't search nearby. Enable it in Settings to find stores.",
                    tint: Tide.text2
                )

            case .failed:
                KitchenNotice(
                    systemImage: "wifi.exclamationmark",
                    text: "Couldn't search nearby stores right now.",
                    tint: Tide.text2,
                    actionTitle: "Try again",
                    action: { Task { await loadNearby() } }
                )

            case let .loaded(results):
                if results.isEmpty {
                    Text("No vitamin or supplement stores found nearby.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                } else {
                    VStack(spacing: 0) {
                        ForEach(results) { result in
                            nearbyRow(result)
                            if result.id != results.last?.id {
                                Rectangle().fill(Tide.hairline).frame(height: 1)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .tideCard(padding: Tide.s4)

                    Text("Stock isn't known — call ahead if you need something specific.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
            }
        }
    }

    private func nearbyRow(_ result: NearbyStoreResult) -> some View {
        Button {
            openInMaps(result)
        } label: {
            HStack {
                Text(result.name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Spacer()
                Text(Self.formatDistance(result.distanceMeters))
                    .font(Tide.numeral(Tide.numeralS, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tide.text2)
                Image(systemName: "chevron.right")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
            .frame(minHeight: Tide.hit)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func openInMaps(_ result: NearbyStoreResult) {
        let mapItem = MKMapItem(location: CLLocation(latitude: result.latitude, longitude: result.longitude), address: nil)
        mapItem.name = result.name
        mapItem.openInMaps()
    }

    // MARK: - Loading

    private func loadPicks() async {
        isLoading = true
        loadErrorMessage = nil
        do {
            let service = SupplementPicksService(apiClient: services.apiClient)
            picks = try await service.fetchPicks(kind: supplement.kind, name: supplement.name)
        } catch {
            loadErrorMessage = "Couldn't load picks. Check your connection and try again."
        }
        isLoading = false
    }

    @MainActor
    private func loadNearby() async {
        nearbyState = .loading
        guard let location = await locationProvider.requestLocation() else {
            nearbyState = locationProvider.isPermanentlyDenied ? .denied : .failed
            return
        }
        let results = await SupplementNearbyStores.around(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        nearbyState = .loaded(results)
    }

    // MARK: - Formatting

    private static func formatPriceAsOf(_ raw: String) -> String? {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.dateFormat = "yyyy-MM"
        guard let date = inputFormatter.date(from: raw) else {
            return nil
        }
        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "en_US_POSIX")
        outputFormatter.dateFormat = "MMM yyyy"
        return outputFormatter.string(from: date)
    }

    private static func formatDistance(_ meters: Double) -> String {
        let miles = meters / 1609.34
        return String(format: "%.1f mi", miles)
    }
}
