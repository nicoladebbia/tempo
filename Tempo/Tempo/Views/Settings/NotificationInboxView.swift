//
// NotificationInboxView.swift
// Tempo
//
// Today's notifications, in the app: what Tempo sent, newest first, and a tap that
// opens what its banner would have opened. Reached from Settings, and from the bell
// (`NotificationBell`) that a screen can put in its toolbar.
//

import SwiftUI
import UserNotifications

// MARK: - NotificationInboxView

struct NotificationInboxView: View {
    /// Called just before a row opens its destination, so the screen that hosts the list can close
    /// itself first (the Settings sheet, or the bell's sheet).
    var onOpen: () -> Void = {}

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.scenePhase)
    private var scenePhase

    /// "Cleared", with Undo.
    @State
    private var toast: ToastData?

    private let inbox = NotificationInbox.shared

    var body: some View {
        TideSettingsPage {
            if inbox.load != .loaded, inbox.items.isEmpty {
                // The list is read in a moment: the page's own shape, breathing.
                LoadingStateView(style: .list)
            } else {
                content
            }
        }
        .navigationTitle("Today's notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !inbox.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            inbox.markAllRead()
                        } label: {
                            Label("Mark all as read", systemImage: "checkmark.circle")
                        }
                        .disabled(inbox.unreadCount == 0)
                        Button(role: .destructive, action: clearToday) {
                            Label("Clear today", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(Tide.bodyStrong)
                            .frame(width: Tide.hit, height: Tide.hit)
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("notificationInboxMenu")
                }
            }
        }
        // At the bottom, clear of the toolbar menu that cleared the list.
        .tempoToast($toast, placement: .bottom)
        .firstTip("notifications.inbox", "Reminders from Tempo collect here for the day. Tap one to open what it is about.", systemImage: "bell")
        .task { await inbox.refresh() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await inbox.refresh() }
            case .background:
                // Leaving the app makes a clear final: there is no toast left to undo from.
                // (Pulling down the shade only makes the app inactive: the toast stays.)
                inbox.commitPendingClear()
                toast = nil
            default:
                break
            }
        }
        // A toast that ran out (or was swiped away) without Undo makes the clear final.
        .onChange(of: toast) { _, newValue in
            if newValue == nil {
                inbox.commitPendingClear()
            }
        }
        .onDisappear { inbox.commitPendingClear() }
    }

    /// Clears today's list at once. They leave Notification Centre when the toast is over.
    private func clearToday() {
        guard inbox.clearTodayWithUndo() != nil else {
            return
        }
        toast = ToastData(message: "Today's notifications cleared.", style: .info, actionTitle: "Undo") {
            inbox.undoClearToday()
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if inbox.authorization == .denied {
            offCard
        }
        if inbox.items.isEmpty {
            emptyCard
        } else {
            summaryCard
            list
        }
    }

    /// Notifications are off in iOS Settings: nothing new can arrive, and the page says so.
    private var offCard: some View {
        TideSettingsHero {
            HStack(spacing: Tide.s3) {
                Image(systemName: "bell.slash.fill")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.settingsAttention)
                    .accessibilityHidden(true)
                Text("Notifications are off")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Tempo can't send you anything until you turn them on in iOS Settings.")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.tideGlass)
            .padding(.top, Tide.s2)
            .accessibilityIdentifier("notificationInboxOpenSettings")
        }
    }

    private var emptyCard: some View {
        TideSettingsHero {
            Image(systemName: "bell")
                .font(Tide.title)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
            Text("Nothing today")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Reminders and alerts that Tempo sends will show up here.")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notificationInboxEmpty")
    }

    private var summaryCard: some View {
        TideSettingsHero {
            TideLabel("Today")
            TideNumber(
                "\(inbox.items.count)", unit: inbox.items.count == 1 ? "notification" : "notifications",
                size: Tide.numeralL, relativeTo: .largeTitle
            )
            Text(inbox.unreadCount == 0 ? "All read." : "\(inbox.unreadCount) not opened yet.")
                .font(Tide.body)
                .foregroundStyle(inbox.unreadCount == 0 ? Tide.text2 : mood.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var list: some View {
        TideSettingsSection(
            footnote: "Today only. A notification you cleared from the lock screen before opening Tempo may be missing."
        ) {
            ForEach(Array(inbox.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    TideSettingsHairline(inset: Tide.s4)
                }
                Button {
                    open(item)
                } label: {
                    row(item)
                }
                .buttonStyle(.tideSettingsRow)
                .accessibilityIdentifier("notificationRow-\(item.category)")
            }
        }
    }

    private func row(_ item: InboxNotification) -> some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            SettingsIconTile(systemName: item.icon, tint: item.isRead ? Tide.text3 : mood.accent)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(item.title)
                    .font(item.isRead ? Tide.body : Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.deliveredAt, format: .dateTime.hour().minute())
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .monospacedDigit()
            }
            Spacer(minLength: Tide.s2)
            if !item.isRead {
                Circle()
                    .fill(mood.accent)
                    .frame(width: Tide.s2, height: Tide.s2)
                    .padding(.top, Tide.s2)
                    .accessibilityHidden(true)
            }
            if item.destination != nil, !typeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .padding(.top, Tide.s1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .frame(maxWidth: .infinity, minHeight: Tide.settingsRow, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isRead ? "" : "Not opened")
    }

    // MARK: Actions

    /// A row opens what its banner would have opened.
    private func open(_ item: InboxNotification) {
        inbox.markRead(item)
        guard item.destination != nil else {
            return
        }
        onOpen()
        Task {
            // Let the sheet that hosts this list finish closing: a destination set while it
            // is still dismissing can be dropped.
            try? await Task.sleep(for: .milliseconds(400))
            await TempoNotificationDelegate.shared.openFromList(item)
        }
    }
}

// MARK: - NotificationBell

/// A bell for a screen's toolbar: a dot when something today has not been opened, and the
/// list of today's notifications behind it.
struct NotificationBell: View {
    /// A glass circle, like the other round controls on Today. Off in a toolbar.
    var glass = false

    @Environment(\.tideMood)
    private var mood
    @Environment(\.scenePhase)
    private var scenePhase

    @State
    private var showInbox = false

    private let inbox = NotificationInbox.shared

    var body: some View {
        Button {
            showInbox = true
        } label: {
            Image(systemName: inbox.unreadCount > 0 ? "bell.badge.fill" : "bell")
                .font(Tide.bodyStrong)
                .foregroundStyle(inbox.unreadCount > 0 ? mood.accent : Tide.text)
                .frame(width: Tide.hit, height: Tide.hit)
                .modifier(BellBackground(glass: glass))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(inbox.unreadCount > 0 ? "Notifications, \(inbox.unreadCount) not opened" : "Notifications")
        .accessibilityIdentifier("notificationBell")
        .sheet(isPresented: $showInbox) {
            NavigationStack {
                NotificationInboxView(onOpen: { showInbox = false })
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showInbox = false }
                                .font(Tide.bodyStrong)
                        }
                    }
            }
        }
        .task { await inbox.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await inbox.refresh() }
            }
        }
    }
}

// MARK: - BellBackground

private struct BellBackground: ViewModifier {
    let glass: Bool

    func body(content: Content) -> some View {
        if glass {
            content.glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
        } else {
            content
        }
    }
}
