//
//  SelectionPanelHeader.swift
//  closet
//

import SwiftUI

enum SelectionActionPlacement {
    /// Leading/trailing controls overlay the title row (e.g. Edit/Done, +).
    case inlineOnTitle
    /// Leading/trailing controls sit in a bar above the title (e.g. Cancel/Done).
    case barAboveTitle
}

struct SelectionPanelHeader<Leading: View, Trailing: View, PickerContent: View>: View {
    let title: String
    var backgroundColor: Color = Color(UIColor.secondarySystemBackground)
    var onTitleTap: (() -> Void)? = nil
    var actionPlacement: SelectionActionPlacement = .inlineOnTitle
    private let showsActions: Bool
    private let showsPicker: Bool
    @ViewBuilder private let leading: () -> Leading
    @ViewBuilder private let trailing: () -> Trailing
    @ViewBuilder private let picker: () -> PickerContent

    private var panelBackground: Color { backgroundColor }

    var body: some View {
        VStack(spacing: 0) {
            if showsActions, actionPlacement == .barAboveTitle {
                actionBar
            }

            titleRow

            if showsPicker {
                pickerBand
            }
        }
    }

    private var actionBar: some View {
        HStack {
            leading()
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(panelBackground)
    }

    @ViewBuilder
    private var titleRow: some View {
        if showsActions, actionPlacement == .inlineOnTitle {
            SelectionHeader(title: title, backgroundColor: backgroundColor, onTitleTap: onTitleTap)
                .overlay {
                    HStack {
                        leading()
                        Spacer()
                        trailing()
                    }
                    .padding(.horizontal, 16)
                }
        } else {
            SelectionHeader(
                title: title,
                backgroundColor: backgroundColor,
                onTitleTap: onTitleTap,
                compactTopSpacing: showsActions && actionPlacement == .barAboveTitle
            )
        }
    }

    private var pickerBand: some View {
        picker()
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(panelBackground)
    }
}

// MARK: - Initializers

extension SelectionPanelHeader where Leading == EmptyView, Trailing == EmptyView, PickerContent == EmptyView {
    init(
        title: String,
        backgroundColor: Color = Color(UIColor.secondarySystemBackground),
        onTitleTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.onTitleTap = onTitleTap
        self.showsActions = false
        self.showsPicker = false
        self.leading = { EmptyView() }
        self.trailing = { EmptyView() }
        self.picker = { EmptyView() }
    }
}

extension SelectionPanelHeader where Leading == EmptyView, Trailing == EmptyView {
    init(
        title: String,
        backgroundColor: Color = Color(UIColor.secondarySystemBackground),
        onTitleTap: (() -> Void)? = nil,
        @ViewBuilder picker: @escaping () -> PickerContent
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.onTitleTap = onTitleTap
        self.showsActions = false
        self.showsPicker = true
        self.leading = { EmptyView() }
        self.trailing = { EmptyView() }
        self.picker = picker
    }
}

extension SelectionPanelHeader where PickerContent == EmptyView {
    init(
        title: String,
        backgroundColor: Color = Color(UIColor.secondarySystemBackground),
        onTitleTap: (() -> Void)? = nil,
        actionPlacement: SelectionActionPlacement = .inlineOnTitle,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.onTitleTap = onTitleTap
        self.actionPlacement = actionPlacement
        self.showsActions = true
        self.showsPicker = false
        self.leading = leading
        self.trailing = trailing
        self.picker = { EmptyView() }
    }
}

extension SelectionPanelHeader {
    init(
        title: String,
        backgroundColor: Color = Color(UIColor.secondarySystemBackground),
        onTitleTap: (() -> Void)? = nil,
        actionPlacement: SelectionActionPlacement = .inlineOnTitle,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder picker: @escaping () -> PickerContent
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.onTitleTap = onTitleTap
        self.actionPlacement = actionPlacement
        self.showsActions = true
        self.showsPicker = true
        self.leading = leading
        self.trailing = trailing
        self.picker = picker
    }
}
