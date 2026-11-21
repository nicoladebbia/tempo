//
// SwipeDeleteList.swift
// Tempo
//
// Rows with swipe-left-to-delete that live inside a page's ScrollView. A
// native List does the swiping, so the Delete button and the row's own tap
// never fight (the old hand-rolled swipe let the row's tap fire instead of
// Delete). The List never scrolls on its own: it is sized from the measured
// rows and the page keeps scrolling.
//

import SwiftUI

struct SwipeDeleteList<Item: Identifiable, Row: View>: View where Item.ID: Hashable {
    /// What the swipe button says and does; nil = this row has no swipe.
    struct SwipeSpec {
        let label: String
        let action: () -> Void
    }

    let items: [Item]
    var rowGap: CGFloat = TempoSpacing.md
    var swipe: (Item) -> SwipeSpec?
    @ViewBuilder
    var row: (Item) -> Row

    @State
    private var heights: [Item.ID: CGFloat] = [:]

    var body: some View {
        List {
            ForEach(items) { item in
                row(item)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: HeightsKey<Item.ID>.self, value: [item.id: proxy.size.height])
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: rowGap / 2, leading: 0, bottom: rowGap / 2, trailing: 0))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let spec = swipe(item) {
                            Button(role: .destructive, action: spec.action) {
                                Label(spec.label, systemImage: "trash.fill")
                            }
                            .tint(Color.tempoError)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .frame(height: totalHeight)
        .onPreferenceChange(HeightsKey<Item.ID>.self) { heights = $0 }
    }

    private var totalHeight: CGFloat {
        items.reduce(CGFloat(0)) { $0 + (heights[$1.id] ?? 90) + rowGap }
    }
}

private struct HeightsKey<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGFloat] { [:] }
    static func reduce(value: inout [ID: CGFloat], nextValue: () -> [ID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
