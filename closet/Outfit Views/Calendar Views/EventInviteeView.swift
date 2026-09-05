//
//  EventInviteeView.swift
//  closet
//
//  Pending event invite preview (Accept / Decline). Host wardrobe is read-only.
//

import SwiftUI

struct EventInviteeView: View {
    let eventId: UUID
    var tabBarHideState: TabBarHideState? = nil
    var onResolved: (() -> Void)? = nil

    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.dismiss) private var dismiss

    @State private var preview: EventInvitePreview?
    @State private var participants: [EventParticipantRecord] = []
    @State private var wardrobeEntries: [EventInviteWardrobeEntry] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var isResponding = false
    @State private var showDeclineConfirm = false

    @State private var isWhoExpanded = true
    @State private var isWhatExpanded = true
    @State private var isWhenExpanded = true
    @State private var isWhereExpanded = true
    @State private var isWardrobeExpanded = true

    private var attributeRowInsets: EdgeInsets {
        EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading invite…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let preview {
                inviteContent(preview)
            } else {
                Text("Invite not available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Event Invite")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(tabBarHideState?.shouldHideTabBar == true ? .hidden : .automatic, for: .tabBar)
        .onAppear { tabBarHideState?.shouldHideTabBar = true }
        .safeAreaInset(edge: .bottom) {
            if preview != nil {
                acceptDeclineBar
            }
        }
        .task(id: eventId) {
            await loadInvite()
        }
        .confirmationDialog(
            "Decline this invitation?",
            isPresented: $showDeclineConfirm,
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) {
                Task { await respond(accept: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can be invited again later.")
        }
        .alert("Couldn’t update invite", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func inviteContent(_ preview: EventInvitePreview) -> some View {
        List {
            Section {
                if isWardrobeExpanded {
                    hostWardrobeHero
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            } header: {
                sectionHeader("WARDROBE", isExpanded: $isWardrobeExpanded)
            }
            .listSectionSpacing(0)

            Section {
                if isWhoExpanded {
                    privacyRow(preview.eventVisibility)
                    whoRows(preview)
                }
            } header: {
                sectionHeader("WHO", isExpanded: $isWhoExpanded)
            }
            .listSectionSpacing(4)

            Section {
                if isWhatExpanded {
                    detailFieldRow(label: "Name", value: displayName(preview))
                    if let occasion = trimmed(preview.occasion) {
                        detailFieldRow(label: "Occasion", value: occasion)
                    }
                    if let theme = trimmed(preview.theme) {
                        detailFieldRow(label: "Theme", value: theme)
                    }
                    if let notes = trimmed(preview.notes) {
                        detailFieldRow(label: "Notes", value: notes, allowsMultiline: true)
                    }
                }
            } header: {
                sectionHeader("WHAT", isExpanded: $isWhatExpanded)
            }
            .listSectionSpacing(4)

            if preview.startDate != nil || preview.endDate != nil {
                Section {
                    if isWhenExpanded, let value = dateTimeCombinedLine(preview) {
                        detailFieldRow(
                            label: "Date & Time",
                            value: value,
                            caption: isAllDay(preview) ? "All-day" : nil,
                            allowsMultiline: !isAllDay(preview) && value.contains("\n"),
                            preventsLabelWrapping: true
                        )
                    }
                } header: {
                    sectionHeader("WHEN", isExpanded: $isWhenExpanded)
                }
                .listSectionSpacing(4)
            }

            if hasLocation(preview) {
                Section {
                    if isWhereExpanded {
                        detailFieldRow(
                            label: "Location",
                            value: locationPrimary(preview),
                            caption: locationCaption(preview)
                        )
                        EventLocationShareActionsRow(
                            shareText: locationShareText(preview),
                            mapsQueryAddress: mapsQueryAddress(preview),
                            latitude: preview.latitude,
                            longitude: preview.longitude,
                            rowInsets: attributeRowInsets
                        )
                    }
                    whereSectionBottomPad
                } header: {
                    sectionHeader("WHERE", isExpanded: $isWhereExpanded)
                }
                .listSectionSpacing(4)
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    private var hostWardrobeHero: some View {
        Color(.systemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if wardrobeEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tshirt")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Host hasn’t added outfits yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(wardrobeEntries.prefix(4)) { entry in
                            EventInviteWardrobeThumb(url: entry.imageURL)
                        }
                    }
                    .padding(12)
                }
            }
            .clipped()
            .accessibilityLabel("Host wardrobe preview")
    }

    private var acceptDeclineBar: some View {
        HStack(spacing: 12) {
            Button {
                showDeclineConfirm = true
            } label: {
                Text("Decline")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isResponding)

            Button {
                Task { await respond(accept: true) }
            } label: {
                if isResponding {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isResponding)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func whoRows(_ preview: EventInvitePreview) -> some View {
        let roster = participants.filter {
            $0.status == "pending" || $0.status == "accepted" || $0.role == "host"
        }
        if roster.isEmpty {
            EventParticipantRow(profile: preview.hostProfile, statusLabel: "Host")
                .listRowInsets(attributeRowInsets)
                .listRowSeparator(.hidden)
        } else {
            ForEach(roster) { participant in
                EventParticipantRow(
                    profile: participant.publicProfile,
                    statusLabel: participant.statusLabel
                        ?? (participant.role == "host" ? "Host" : "Invited")
                )
                .listRowInsets(attributeRowInsets)
                .listRowSeparator(.hidden)
            }
        }
    }

    private func privacyRow(_ visibility: WardrobeVisibility) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Profile Visibility")
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: visibility.iconName)
                    .foregroundColor(.gray)
                Text(visibility.menuLabel)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .listRowInsets(attributeRowInsets)
        .listRowSeparator(.hidden)
    }

    private var whereSectionBottomPad: some View {
        Color.clear
            .frame(height: 4)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .environment(\.defaultMinListRowHeight, 1)
    }

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
            Spacer()
            Image(systemName: isExpanded.wrappedValue ? "minus" : "plus")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.wrappedValue.toggle()
            }
        }
    }

    private func detailFieldRow(
        label: String,
        value: String,
        caption: String? = nil,
        allowsMultiline: Bool = false,
        preventsLabelWrapping: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: preventsLabelWrapping, vertical: false)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(allowsMultiline ? nil : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: allowsMultiline)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
        }
        .listRowInsets(attributeRowInsets)
        .listRowSeparator(.hidden)
    }

    private func loadInvite() async {
        isLoading = true
        loadError = nil
        do {
            async let previewTask = supabaseService.fetchEventInvitePreview(eventId: eventId)
            async let participantsTask = supabaseService.fetchEventParticipants(eventId: eventId)
            async let wardrobeTask = supabaseService.fetchEventInviteWardrobe(eventId: eventId)
            let (p, parts, wardrobe) = try await (previewTask, participantsTask, wardrobeTask)
            preview = p
            participants = parts
            wardrobeEntries = wardrobe
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    private func respond(accept: Bool) async {
        guard !isResponding else { return }
        isResponding = true
        actionError = nil
        do {
            try await supabaseService.respondToEventInvite(eventId: eventId, accept: accept)
            if accept {
                try await SyncService.shared.materializeAcceptedGuestEvent(eventId: eventId)
            }
            onResolved?()
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
        isResponding = false
    }

    // MARK: - Formatting

    private func trimmed(_ value: String?) -> String? {
        let t = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    private func displayName(_ preview: EventInvitePreview) -> String {
        trimmed(preview.name) ?? "Untitled Event"
    }

    private func isAllDay(_ preview: EventInvitePreview) -> Bool {
        guard let start = preview.startDate, let end = preview.endDate else { return false }
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        return (startComponents.hour == 0 && startComponents.minute == 0)
            && (endComponents.hour == 0 && endComponents.minute == 0)
    }

    private func compactTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let hour24 = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        var text = "\(hour12)"
        if minute != 0 { text += String(format: ":%02d", minute) }
        text += hour24 < 12 ? "AM" : "PM"
        return text
    }

    private func dateTimeLine(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return "\(formatter.string(from: date)) · \(compactTime(date))"
    }

    private func dateTimeCombinedLine(_ preview: EventInvitePreview) -> String? {
        guard let startDate = preview.startDate else { return nil }
        let endDate = preview.endDate ?? startDate
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        if isAllDay(preview) {
            let startText = formatter.string(from: startDate)
            if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                return startText
            }
            return "\(startText) – \(formatter.string(from: endDate))"
        }
        return "\(dateTimeLine(for: startDate))\n\(dateTimeLine(for: endDate))"
    }

    private func hasLocation(_ preview: EventInvitePreview) -> Bool {
        trimmed(preview.location) != nil || trimmed(preview.fullAddress) != nil
    }

    private func locationPrimary(_ preview: EventInvitePreview) -> String {
        if let name = trimmed(preview.location) { return name }
        return trimmed(preview.fullAddress) ?? ""
    }

    private func locationCaption(_ preview: EventInvitePreview) -> String? {
        guard trimmed(preview.location) != nil else { return nil }
        return trimmed(preview.fullAddress)
    }

    private func locationShareText(_ preview: EventInvitePreview) -> String {
        let name = trimmed(preview.location) ?? ""
        let address = trimmed(preview.fullAddress) ?? ""
        if !name.isEmpty, !address.isEmpty { return "\(name)\n\(address)" }
        if !address.isEmpty { return address }
        return name
    }

    private func mapsQueryAddress(_ preview: EventInvitePreview) -> String? {
        trimmed(preview.fullAddress) ?? trimmed(preview.location)
    }
}

private struct EventInviteWardrobeThumb: View {
    let url: URL?

    var body: some View {
        Color(.systemGray6)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        default:
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
