//
//  EventDetailLayoutPrototypeView.swift
//  closet
//
//  Layout lab only. Fake event data. Not used by Calendar, EventAddView, or EventDetailView.
//  Open from Developer Settings → Event Detail layout prototype.
//  Default: Detail. Pencil (trailing toolbar) toggles Edit.
//

import SwiftUI

struct EventDetailLayoutPrototypeView: View {
    @State private var isEditing = false
    @State private var eventVisibility: WardrobeVisibility = .friends
    @State private var isWhatExpanded = true
    @State private var isWhenExpanded = true
    @State private var isWhereExpanded = true
    @State private var isWhoExpanded = true

    private let sampleName = "Summer Garden Party"
    private let sampleTheme = "Floral, garden, pastels"
    private let sampleNotes = "Bring a light jacket after sunset. Host is providing drinks."
    private let sampleDate = "Saturday, August 22, 2026"
    private let sampleTime = "6–9:30PM"
    private let sampleLocation = "Harbor Park"
    private let sampleAddress = "Pier 3, Waterfront Drive"

    private let sampleOwnUser = PublicUserProfile(
        userId: UUID(uuidString: "00000000-0000-4000-8000-000000000000")!,
        username: "you",
        displayName: "Dan Warner",
        avatarUrl: nil
    )

    private let sampleGuestParticipants: [PublicUserProfile] = [
        PublicUserProfile(
            userId: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            username: "alex",
            displayName: "Alex Chen",
            avatarUrl: nil
        ),
        PublicUserProfile(
            userId: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            username: "jordan",
            displayName: "Jordan Lee",
            avatarUrl: nil
        )
    ]

    private var sampleParticipants: [PublicUserProfile] {
        [sampleOwnUser] + sampleGuestParticipants
    }

    private var isOnlyOwnUserParticipant: Bool {
        sampleGuestParticipants.isEmpty
    }

    var body: some View {
        Group {
            if isEditing {
                editLayout
            } else {
                detailLayout
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        isEditing.toggle()
                    }
                } label: {
                    Image(systemName: "pencil")
                        .symbolVariant(isEditing ? .fill : .none)
                }
                .accessibilityLabel(isEditing ? "Show detail layout" : "Show edit layout")
            }
        }
    }

    // MARK: - Edit (current List prototype)

    private var editLayout: some View {
        List {
            Section {
                blankItemsOutfitsArea
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            .listSectionSpacing(4)

            Section {
                if isWhoExpanded {
                    privacyPickerRow
                    ForEach(sampleParticipants) { profile in
                        prototypeParticipantRow(profile)
                    }
                }
            } header: {
                prototypeSectionHeader("WHO", isExpanded: $isWhoExpanded)
            }
            .listSectionSpacing(4)

            Section {
                if isWhatExpanded {
                    editFieldRow(label: "Name", value: sampleName)
                    editFieldRow(label: "Theme", value: sampleTheme)
                    editFieldRow(label: "Notes", value: sampleNotes, allowsMultiline: true)
                }
            } header: {
                prototypeSectionHeader("WHAT", isExpanded: $isWhatExpanded)
            }
            .listSectionSpacing(4)

            Section {
                if isWhenExpanded {
                    editFieldRow(label: "Date", value: sampleDate)
                    editFieldRow(label: "Time", value: sampleTime)
                }
            } header: {
                prototypeSectionHeader("WHEN", isExpanded: $isWhenExpanded)
            }
            .listSectionSpacing(4)

            Section {
                if isWhereExpanded {
                    editFieldRow(label: "Location", value: sampleLocation)
                    editFieldRow(label: "Address", value: sampleAddress)
                }
            } header: {
                prototypeSectionHeader("WHERE", isExpanded: $isWhereExpanded)
            }
            .listSectionSpacing(4)
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
    }

    // MARK: - Detail (same rows as edit, no separators/chevrons on What/When/Where)

    private var detailLayout: some View {
        List {
            Section {
                blankItemsOutfitsArea
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            .listSectionSpacing(4)

            Section {
                if isWhoExpanded {
                    privacyReadOnlyRow
                    ForEach(sampleParticipants) { profile in
                        prototypeParticipantRow(profile)
                    }
                }
            } header: {
                prototypeSectionHeader("WHO", isExpanded: $isWhoExpanded)
            }
            .listSectionSpacing(4)

            Section {
                if isWhatExpanded {
                    detailFieldRow(label: "Name", value: sampleName)
                    detailFieldRow(label: "Theme", value: sampleTheme)
                    detailFieldRow(label: "Notes", value: sampleNotes, allowsMultiline: true)
                }
            } header: {
                prototypeSectionHeader("WHAT", isExpanded: $isWhatExpanded)
            }
            .listSectionSpacing(4)

            Section {
                if isWhenExpanded {
                    detailFieldRow(label: "Date", value: sampleDate)
                    detailFieldRow(label: "Time", value: sampleTime)
                }
            } header: {
                prototypeSectionHeader("WHEN", isExpanded: $isWhenExpanded)
            }
            .listSectionSpacing(4)

            Section {
                if isWhereExpanded {
                    detailFieldRow(label: "Location", value: sampleLocation)
                    detailFieldRow(label: "Address", value: sampleAddress)
                }
            } header: {
                prototypeSectionHeader("WHERE", isExpanded: $isWhereExpanded)
            }
            .listSectionSpacing(4)
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
    }

    private var blankItemsOutfitsArea: some View {
        Color(.systemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Tap to add items or outfits")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tap to add items or outfits")
    }

    private var attributeRowInsets: EdgeInsets {
        EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20)
    }

    private var privacyPickerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: eventVisibility.iconName)
                .foregroundColor(.gray)
                .frame(width: 22)
            Picker("Privacy", selection: $eventVisibility) {
                ForEach(WardrobeVisibility.allCases) { value in
                    Text(value.menuLabel).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer(minLength: 0)
        }
        .listRowSeparator(.hidden)
    }

    private var privacyReadOnlyRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: eventVisibility.iconName)
                .foregroundColor(.gray)
                .frame(width: 22)
            Text(eventVisibility.menuLabel)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .listRowSeparator(.hidden)
    }

    private func prototypeParticipantRow(_ profile: PublicUserProfile) -> some View {
        let isOwnUser = profile.userId == sampleOwnUser.userId
        let statusText: String = {
            if isOwnUser {
                return isOnlyOwnUserParticipant ? "Only You" : "You"
            }
            return "Invited"
        }()

        return HStack(spacing: 12) {
            PublicUserProfileAvatarView(profile: profile, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.username)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let displayName = profile.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    private func editFieldRow(label: String, value: String, allowsMultiline: Bool = false) -> some View {
        attributeFieldRow(label: label, value: value, allowsMultiline: allowsMultiline, showsChevron: true)
    }

    /// Same layout as edit, without chevron or list separators.
    private func detailFieldRow(label: String, value: String, allowsMultiline: Bool = false) -> some View {
        attributeFieldRow(label: label, value: value, allowsMultiline: allowsMultiline, showsChevron: false)
            .listRowSeparator(.hidden)
    }

    private func attributeFieldRow(
        label: String,
        value: String,
        allowsMultiline: Bool,
        showsChevron: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(.primary)
            Spacer(minLength: 8)
            HStack(alignment: .top, spacing: 8) {
                Text(value)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(allowsMultiline ? nil : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: allowsMultiline)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .font(.caption)
                        .padding(.top, 4)
                }
            }
            .containerRelativeFrame(.horizontal, alignment: .trailing) { length, _ in
                length * 0.6
            }
        }
        .listRowInsets(attributeRowInsets)
    }

    private func prototypeSectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
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
}
