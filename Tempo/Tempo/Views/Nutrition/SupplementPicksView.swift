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
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                if isLoading {
                    loadingState
                } else if let loadErrorMessage {
                    errorState(loadErrorMessage)
                } else if let picks {
                    content(for: picks)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.md)
            .padding(.bottom, TempoSpacing.bottomSafe)
        }
        .background(Color.tempoBgPrimary.ignoresSafeArea())
        .navigationTitle("Best \(supplement.kind.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPicks()
        }
    }

    // MARK: - Loading / error

    private var loadingState: some View {
        VStack {
            ProgressView()
            Text("Finding the best picks…")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxxl)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            // Icon size/color per DESIGN_SYSTEM.md §12.5 (Full-Screen Error) —
            // same convention as the shared ErrorStateView component.
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.tempoError)
            Text(message)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await loadPicks() }
            }
            .buttonStyle(.tempoSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxxl)
    }

    // MARK: - Content

    private func content(for picks: SupplementPicksDTO) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            if let lookFor = picks.lookFor, !lookFor.isEmpty {
                lookForCard(lookFor)
            }

            if !picks.verified {
                unverifiedBanner
            }

            if picks.picks.isEmpty {
                emptyPicksState
            } else {
                VStack(spacing: TempoSpacing.md) {
                    ForEach(picks.picks, id: \.id) { pick in
                        pickCard(pick)
                    }
                }
            }

            nearbySection
        }
    }

    private func lookForCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("WHAT TO LOOK FOR")
                .font(.tempoModuleTag)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(text)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private var unverifiedBanner: some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.tempoWarning)
            Text("AI suggestions — not verified. Double-check any certification claim yourself before buying.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(TempoSpacing.cardPaddingCompact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoWarning.opacity(TempoOpacity.o10))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    private var emptyPicksState: some View {
        Text("No suggestions available for this one right now. Try again later, or search for a third-party certified option yourself.")
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func pickCard(_ pick: SupplementPicksDTO.Pick) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(pick.brand)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                Text(pick.product)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                if let form = pick.form, !form.isEmpty {
                    Text(form.capitalized)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }

            if !pick.certifications.isEmpty {
                HStack(spacing: TempoSpacing.xs) {
                    ForEach(pick.certifications, id: \.self) { certification in
                        certificationBadge(certification)
                    }
                }
            }

            Text(pick.why)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)

            if pick.approxPricePerServingUSD != nil {
                Text(priceLine(for: pick))
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            if !pick.buyLinks.isEmpty {
                HStack(spacing: TempoSpacing.sm) {
                    ForEach(pick.buyLinks, id: \.url) { link in
                        buyLinkButton(link)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
        Text(text.uppercased())
            .font(.tempoCaption2)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tempoSuccess)
            .padding(.horizontal, TempoSpacing.sm)
            .padding(.vertical, TempoSpacing.xxs)
            .background(Color.tempoSuccess.opacity(TempoOpacity.o15))
            .clipShape(Capsule())
    }

    private func buyLinkButton(_ link: SupplementPicksDTO.BuyLink) -> some View {
        Button {
            if let url = URL(string: link.url) {
                openURL(url)
            }
        } label: {
            Text(link.label)
                .font(.tempoCaption1)
                .fontWeight(.semibold)
        }
        .buttonStyle(.tempoGhost)
    }

    // MARK: - Nearby

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("NEARBY STORES")
                .font(.tempoModuleTag)
                .foregroundStyle(Color.tempoTextTertiary)

            switch nearbyState {
            case .idle:
                Button {
                    Task { await loadNearby() }
                } label: {
                    Label("Find Nearby Stores", systemImage: "location")
                }
                .buttonStyle(.tempoSecondary)

            case .loading:
                HStack {
                    ProgressView()
                    Text("Searching nearby…")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

            case .denied:
                Text("Location access is off, so we can't search nearby. Enable it in Settings to find stores.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)

            case .failed:
                Text("Couldn't search nearby stores right now.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)

            case let .loaded(results):
                if results.isEmpty {
                    Text("No vitamin or supplement stores found nearby.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(results) { result in
                            nearbyRow(result)
                            if result.id != results.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(TempoSpacing.cardPadding)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                    Text("Stock isn't known — call ahead if you need something specific.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
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
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Text(Self.formatDistance(result.distanceMeters))
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                Image(systemName: "chevron.right")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(.vertical, TempoSpacing.xs)
        }
        .buttonStyle(.plain)
    }

    private func openInMaps(_ result: NearbyStoreResult) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude))
        let mapItem = MKMapItem(placemark: placemark)
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
