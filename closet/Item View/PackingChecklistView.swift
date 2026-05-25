//
//  PackingChecklistView.swift
//  closet
//

import SwiftUI
import CoreData

private enum PackingChecklistKind: Int16 {
    case items = 0
    case todo = 1

    var segmentTag: String {
        switch self {
        case .items: return "Items"
        case .todo: return "To-Do"
        }
    }

    static func fromSegment(_ tag: String) -> PackingChecklistKind {
        tag == "To-Do" ? .todo : .items
    }
}

/// Flat list rows for edit mode — section headers are fixed; items can move across sections.
private struct ChecklistListRow: Identifiable {
    enum RowKind {
        case sectionHeader(PackingChecklistSection)
        case item(PackingChecklistItem)
    }

    let id: String
    let kind: RowKind

    var isItem: Bool {
        if case .item = kind { return true }
        return false
    }
}

struct PackingChecklistView: View {
    @ObservedObject var selectedWardrobe: Wardrobe
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var checklistEditMode: EditMode = .inactive

    @State private var showNewSectionAlert = false
    @State private var newSectionName = ""

    @State private var showEditSectionAlert = false
    @State private var editingSectionTitle = ""
    @State private var sectionBeingRenamed: PackingChecklistSection?

    @State private var selectedTab = "Items"
    @FocusState private var focusedRowID: UUID?

    /// Batches Core Data flushes during typing — no sync per keystroke.
    @State private var debouncedLocalSaveTask: Task<Void, Never>?

    @FetchRequest private var sectionsFetched: FetchedResults<PackingChecklistSection>

    private let textTypingDebounceNanoseconds: UInt64 = 380_000_000

    private var reorderEditingActive: Bool {
        checklistEditMode == .active
    }

    init(selectedWardrobe: Wardrobe) {
        self._selectedWardrobe = ObservedObject(wrappedValue: selectedWardrobe)
        let wardrobe = selectedWardrobe

        let sectionReq: NSFetchRequest<PackingChecklistSection> = PackingChecklistSection.fetchRequest()
        sectionReq.sortDescriptors = [
            NSSortDescriptor(keyPath: \PackingChecklistSection.kind, ascending: true),
            NSSortDescriptor(keyPath: \PackingChecklistSection.sortIndex, ascending: true)
        ]
        sectionReq.predicate = NSPredicate(format: "wardrobe == %@", wardrobe)
        _sectionsFetched = FetchRequest(fetchRequest: sectionReq, animation: .default)
    }

    var body: some View {
        VStack(spacing: 0) {
            SelectionHeader(title: "Checklist")
                .overlay {
                    HStack {
                        Button(checklistEditMode == .active ? "Done" : "Edit") {
                            toggleChecklistEditMode()
                        }
                        Spacer()
                        Button {
                            newSectionName = ""
                            showNewSectionAlert = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(reorderEditingActive)
                        .accessibilityLabel("Add section")
                    }
                    .padding(.horizontal, 16)
                }

            Picker("", selection: $selectedTab) {
                Text("Items")
                    .tag("Items")
                Text("To-Do")
                    .tag("To-Do")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))
            .disabled(reorderEditingActive)

            Group {
                if reorderEditingActive {
                    checklistList(kind: PackingChecklistKind.fromSegment(selectedTab))
                } else {
                    TabView(selection: $selectedTab) {
                        checklistList(kind: .items).tag("Items")
                        checklistList(kind: .todo).tag("To-Do")
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .background(Color(UIColor.systemBackground))
            .environment(\.editMode, $checklistEditMode)
        }
        .onAppear {
            migrateChecklistSectionsIfNeeded()
            ensureSeedRowsForAllSections()
            scheduleFocusFirstRow(for: selectedTab)
        }
        .onDisappear {
            if checklistEditMode == .active {
                ensureSeedRowsForAllSections()
            }
            checklistEditMode = .inactive
            flushPendingChecklistPersistAndRemoteSync()
        }
        .onChange(of: selectedTab) { _, _ in
            invalidateDebouncedLocalSaveTask()
            saveCoreDataLocallyOnly()
        }
        .onChange(of: focusedRowID) { _, _ in
            commitInlineTextEditsToStore()
        }
        .onChange(of: checklistEditMode) { _, newMode in
            if newMode == .active {
                invalidateDebouncedLocalSaveTask()
                focusedRowID = nil
                saveCoreDataLocallyOnly()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                flushPendingChecklistPersistAndRemoteSync()
            }
        }
        .alert("New Section", isPresented: $showNewSectionAlert) {
            TextField("Section name", text: $newSectionName)
                .textInputAutocapitalization(.words)
            Button("Add") {
                createSectionFromAlert()
                newSectionName = ""
            }
            Button("Cancel", role: .cancel) {
                newSectionName = ""
            }
        } message: {
            Text("Enter a name for the new section in the \(selectedTab) checklist.")
        }
        .alert("Rename Section", isPresented: $showEditSectionAlert) {
            TextField("Section name", text: $editingSectionTitle)
                .textInputAutocapitalization(.words)
            Button("Save") {
                applySectionTitleFromAlert()
                editingSectionTitle = ""
                sectionBeingRenamed = nil
            }
            Button("Cancel", role: .cancel) {
                editingSectionTitle = ""
                sectionBeingRenamed = nil
            }
        } message: {
            Text("Enter a title for this section.")
        }
    }

    private func toggleChecklistEditMode() {
        if checklistEditMode == .active {
            checklistEditMode = .inactive
            ensureSeedRowsForAllSections()
        } else {
            checklistEditMode = .active
        }
        focusedRowID = nil
    }

    // MARK: - Sections

    private func sections(kind: PackingChecklistKind) -> [PackingChecklistSection] {
        sectionsFetched.filter { $0.kind == kind.rawValue }
    }

    private func displayTitle(for section: PackingChecklistSection) -> String {
        let trimmed = (section.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "GENERAL" }
        return trimmed
    }

    /// Ensures each checklist tab has at least one section (GENERAL by default) for this wardrobe.
    private func migrateChecklistSectionsIfNeeded() {
        for kind in [PackingChecklistKind.items, .todo] {
            let existing = sections(kind: kind)
            if existing.isEmpty {
                let defaultTitle: String
                if kind == .items {
                    let legacy = (selectedWardrobe.packingChecklistSectionTitle ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    defaultTitle = legacy.isEmpty ? "GENERAL" : legacy
                } else {
                    defaultTitle = "GENERAL"
                }
                let section = makeChecklistSection(title: defaultTitle, kind: kind, sortIndex: 0)
                attachOrphanItems(to: section, kind: kind)
                continue
            }
            if let first = existing.first {
                attachOrphanItems(to: first, kind: kind)
            }
        }
        saveCoreDataLocallyOnly()
    }

    private func attachOrphanItems(to section: PackingChecklistSection, kind: PackingChecklistKind) {
        let request: NSFetchRequest<PackingChecklistItem> = PackingChecklistItem.fetchRequest()
        request.predicate = NSPredicate(
            format: "wardrobe == %@ AND kind == %d AND section == nil",
            selectedWardrobe,
            kind.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PackingChecklistItem.sortIndex, ascending: true)]
        guard let orphans = try? viewContext.fetch(request), !orphans.isEmpty else { return }
        for item in orphans {
            item.section = section
        }
        reassignSortIndices(rows(in: section))
    }

    private func makeChecklistSection(title: String, kind: PackingChecklistKind, sortIndex: Int32) -> PackingChecklistSection {
        let section = PackingChecklistSection(context: viewContext)
        section.id = UUID()
        section.title = title
        section.kind = kind.rawValue
        section.sortIndex = sortIndex
        section.wardrobe = selectedWardrobe
        if let userId = authSession.userId?.uuidString {
            section.userId = userId
        }
        setCreatedAndUpdatedAt(section)
        return section
    }

    private func createSectionFromAlert() {
        let trimmed = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let kind = PackingChecklistKind.fromSegment(selectedTab)
        let nextIndex = Int32(sections(kind: kind).count)
        let section = makeChecklistSection(title: trimmed, kind: kind, sortIndex: nextIndex)
        ensureSeedRowIfNeeded(section: section)
        saveCoreDataLocallyOnly()
        SyncService.shared.syncPackingChecklistSectionIfNeeded(section)
        DispatchQueue.main.async {
            if let firstRow = rows(in: section).first?.id {
                focusedRowID = firstRow
            }
        }
    }

    private func applySectionTitleFromAlert() {
        guard let section = sectionBeingRenamed else { return }
        let trimmed = editingSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        section.title = trimmed
        setUpdatedAt(section)
        if section.userId == nil || section.userId?.isEmpty == true,
           let uid = authSession.userId?.uuidString {
            section.userId = uid
        }
        do {
            try viewContext.save()
            SyncService.shared.syncPackingChecklistSectionIfNeeded(section)
        } catch {
            print("❌ PackingChecklistView failed to save section title: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private func checklistSectionHeader(_ section: PackingChecklistSection) -> some View {
        HStack {
            Text(displayTitle(for: section).uppercased())
                .fontWeight(.semibold)
                .foregroundColor(.gray)
                .font(.subheadline)
            Spacer()
            Button {
                sectionBeingRenamed = section
                editingSectionTitle = (section.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                showEditSectionAlert = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .disabled(reorderEditingActive)
        }
        .padding(.horizontal, 4)
        .textCase(nil)
    }

    private func rows(in section: PackingChecklistSection) -> [PackingChecklistItem] {
        let set = section.items as? Set<PackingChecklistItem> ?? []
        return set.sorted { $0.sortIndex < $1.sortIndex }
    }

    private func incompleteRows(in section: PackingChecklistSection) -> [PackingChecklistItem] {
        rows(in: section).filter { !$0.isCompleted }
    }

    private func completedRows(in section: PackingChecklistSection) -> [PackingChecklistItem] {
        rows(in: section).filter { $0.isCompleted }
    }

    private func uuidOfFirstRow(for tab: String) -> UUID? {
        let kind = PackingChecklistKind.fromSegment(tab)
        guard let section = sections(kind: kind).first else { return nil }
        return rows(in: section).first?.id
    }

    private func scheduleFocusFirstRow(for tab: String) {
        guard let id = uuidOfFirstRow(for: tab) else { return }
        DispatchQueue.main.async {
            focusedRowID = id
        }
    }

    // MARK: - Persistence (debounced typing, flush on checkpoints)

    private func invalidateDebouncedLocalSaveTask() {
        debouncedLocalSaveTask?.cancel()
        debouncedLocalSaveTask = nil
    }

    private func scheduleDebouncedCoreDataSaveAfterTyping() {
        debouncedLocalSaveTask?.cancel()
        debouncedLocalSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: textTypingDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            saveCoreDataLocallyOnly()
            debouncedLocalSaveTask = nil
        }
    }

    private func commitInlineTextEditsToStore() {
        invalidateDebouncedLocalSaveTask()
        saveCoreDataLocallyOnly()
    }

    private func saveCoreDataLocallyOnly() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            print("❌ PackingChecklistView Core Data save failed: \(error.localizedDescription)")
        }
    }

    private func flushPendingChecklistPersistAndRemoteSync() {
        invalidateDebouncedLocalSaveTask()
        saveCoreDataLocallyOnly()
        for section in sectionsFetched {
            SyncService.shared.syncPackingChecklistSectionIfNeeded(section)
        }
        for section in sectionsFetched {
            for row in rows(in: section) {
                SyncService.shared.syncPackingChecklistItemIfNeeded(row)
            }
        }
    }

    private func ensureSeedRowsForAllSections() {
        for section in sectionsFetched {
            ensureSeedRowIfNeeded(section: section)
        }
    }

    private func ensureSeedRowIfNeeded(section: PackingChecklistSection) {
        guard rows(in: section).isEmpty else { return }
        let kind = PackingChecklistKind(rawValue: section.kind) ?? .items
        let obj = PackingChecklistItem(context: viewContext)
        obj.id = UUID()
        obj.text = ""
        obj.isCompleted = false
        obj.kind = kind.rawValue
        obj.sortIndex = 0
        obj.wardrobe = selectedWardrobe
        obj.section = section
        if let userId = authSession.userId?.uuidString {
            obj.userId = userId
        }
        setCreatedAndUpdatedAt(obj)
        invalidateDebouncedLocalSaveTask()
        saveCoreDataLocallyOnly()
    }

    private func reassignSortIndices(_ items: [PackingChecklistItem]) {
        for (i, o) in items.enumerated() {
            o.sortIndex = Int32(i)
            setUpdatedAt(o)
        }
    }

    private func appendRowBelow(rowID: UUID, section: PackingChecklistSection) {
        guard !reorderEditingActive else { return }
        var list = rows(in: section)
        guard let idx = list.firstIndex(where: { $0.id == rowID }) else { return }
        invalidateDebouncedLocalSaveTask()

        let kind = PackingChecklistKind(rawValue: section.kind) ?? .items
        let obj = PackingChecklistItem(context: viewContext)
        obj.id = UUID()
        obj.text = ""
        obj.isCompleted = false
        obj.kind = kind.rawValue
        obj.wardrobe = selectedWardrobe
        obj.section = section
        if let userId = authSession.userId?.uuidString {
            obj.userId = userId
        }
        setCreatedAndUpdatedAt(obj)
        list.insert(obj, at: idx + 1)
        reassignSortIndices(list)
        saveCoreDataLocallyOnly()
        DispatchQueue.main.async {
            focusedRowID = obj.id
        }
    }

    private func moveIncompleteRows(
        section: PackingChecklistSection,
        source: IndexSet,
        destination: Int
    ) {
        invalidateDebouncedLocalSaveTask()
        var incomplete = incompleteRows(in: section)
        let completed = completedRows(in: section)
        incomplete.move(fromOffsets: source, toOffset: destination)
        reassignSortIndices(incomplete + completed)
        saveCoreDataLocallyOnly()
    }

    private func moveCompletedRows(
        section: PackingChecklistSection,
        source: IndexSet,
        destination: Int
    ) {
        invalidateDebouncedLocalSaveTask()
        let incomplete = incompleteRows(in: section)
        var completed = completedRows(in: section)
        completed.move(fromOffsets: source, toOffset: destination)
        reassignSortIndices(incomplete + completed)
        saveCoreDataLocallyOnly()
    }

    // MARK: - Edit-mode list (cross-section reorder)

    private func editModeListRows(kind: PackingChecklistKind) -> [ChecklistListRow] {
        var result: [ChecklistListRow] = []
        for section in sections(kind: kind) {
            result.append(ChecklistListRow(
                id: "header-\(section.objectID.uriRepresentation().absoluteString)",
                kind: .sectionHeader(section)
            ))
            for item in incompleteRows(in: section) {
                result.append(ChecklistListRow(
                    id: "item-\(item.objectID.uriRepresentation().absoluteString)",
                    kind: .item(item)
                ))
            }
            for item in completedRows(in: section) {
                result.append(ChecklistListRow(
                    id: "item-\(item.objectID.uriRepresentation().absoluteString)",
                    kind: .item(item)
                ))
            }
        }
        return result
    }

    private func applyEditModeMove(kind: PackingChecklistKind, from source: IndexSet, to destination: Int) {
        invalidateDebouncedLocalSaveTask()
        var rows = editModeListRows(kind: kind)
        guard source.allSatisfy({ rows[$0].isItem }) else { return }
        rows.move(fromOffsets: source, toOffset: destination)
        persistEditModeRowOrder(rows, kind: kind)
        saveCoreDataLocallyOnly()
    }

    /// Assigns each item to the section above it in the flat list, then incomplete-before-completed per section.
    private func persistEditModeRowOrder(_ rows: [ChecklistListRow], kind: PackingChecklistKind) {
        var currentSection: PackingChecklistSection?
        var itemsBySection: [NSManagedObjectID: [PackingChecklistItem]] = [:]

        for row in rows {
            switch row.kind {
            case .sectionHeader(let section):
                currentSection = section
            case .item(let item):
                guard let section = currentSection else { continue }
                item.section = section
                item.kind = kind.rawValue
                itemsBySection[section.objectID, default: []].append(item)
            }
        }

        for section in sections(kind: kind) {
            let ordered = itemsBySection[section.objectID] ?? []
            let incomplete = ordered.filter { !$0.isCompleted }
            let completed = ordered.filter { $0.isCompleted }
            reassignSortIndices(incomplete + completed)
        }
    }

    @ViewBuilder
    private func checklistList(kind: PackingChecklistKind) -> some View {
        if reorderEditingActive {
            editModeChecklistList(kind: kind)
        } else {
            normalChecklistList(kind: kind)
        }
    }

    @ViewBuilder
    private func editModeChecklistList(kind: PackingChecklistKind) -> some View {
        let rows = editModeListRows(kind: kind)

        List {
            ForEach(rows) { row in
                switch row.kind {
                case .sectionHeader(let section):
                    checklistSectionHeader(section)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden, edges: .top)
                        .listRowBackground(Color(UIColor.systemBackground))
                        .moveDisabled(true)

                case .item(let item):
                    let section = item.section ?? sections(kind: kind).first!
                    checklistRow(item: item, section: section)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 8))
                        .listRowSeparator(.visible, edges: .bottom)
                        .listRowBackground(Color(UIColor.systemBackground))
                }
            }
            .onMove { source, destination in
                applyEditModeMove(kind: kind, from: source, to: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(UIColor.systemBackground))
    }

    @ViewBuilder
    private func normalChecklistList(kind: PackingChecklistKind) -> some View {
        let sectionList = sections(kind: kind)

        List {
            ForEach(sectionList, id: \.objectID) { section in
                let incomplete = incompleteRows(in: section)
                let completed = completedRows(in: section)

                Section(header: checklistSectionHeader(section)) {
                    ForEach(incomplete, id: \.objectID) { item in
                        checklistRow(item: item, section: section)
                            .focused($focusedRowID, equals: item.id)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 8))
                            .listRowSeparator(.visible, edges: .bottom)
                            .listRowBackground(Color(UIColor.systemBackground))
                    }
                    .onMove { source, destination in
                        moveIncompleteRows(section: section, source: source, destination: destination)
                    }

                    if !completed.isEmpty {
                        ForEach(completed, id: \.objectID) { item in
                            checklistRow(item: item, section: section)
                                .focused($focusedRowID, equals: item.id)
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 8))
                                .listRowSeparator(.visible, edges: .bottom)
                                .listRowBackground(Color(UIColor.systemBackground))
                        }
                        .onMove { source, destination in
                            moveCompletedRows(section: section, source: source, destination: destination)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(UIColor.systemBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func checklistRow(item: PackingChecklistItem, section: PackingChecklistSection) -> some View {
        let completed = item.isCompleted
        let rowId = item.id

        let rowCore = HStack(alignment: .center, spacing: 12) {
            Button {
                guard let id = rowId else { return }
                toggleComplete(rowID: id, section: section)
            } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(completed ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(reorderEditingActive)
            .accessibilityLabel(completed ? "Mark incomplete" : "Mark complete")

            TextField(
                "",
                text: textBinding(for: item)
            )
            .lineLimit(1)
            .textFieldStyle(.plain)
            .foregroundStyle(completed ? Color.secondary : Color.primary)
            .strikethrough(completed, pattern: .solid, color: .secondary)
            .disabled(reorderEditingActive)
            .accessibilityHint("Checklist entry")
            .submitLabel(.return)
            .onSubmit {
                guard let id = rowId else { return }
                appendRowBelow(rowID: id, section: section)
            }
        }
        .opacity(completed ? 0.75 : 1)

        Group {
            if reorderEditingActive {
                rowCore
            } else {
                rowCore
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            guard let id = rowId else { return }
                            deleteRow(rowID: id, section: section)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func textBinding(for item: PackingChecklistItem) -> Binding<String> {
        Binding(
            get: { item.text ?? "" },
            set: { newVal in
                item.text = newVal
                setUpdatedAt(item)
                scheduleDebouncedCoreDataSaveAfterTyping()
            }
        )
    }

    private func toggleComplete(rowID: UUID, section: PackingChecklistSection) {
        guard !reorderEditingActive else { return }
        invalidateDebouncedLocalSaveTask()
        var list = rows(in: section)
        guard let idx = list.firstIndex(where: { $0.id == rowID }) else { return }
        list[idx].isCompleted.toggle()
        let reordered = list.filter { !$0.isCompleted } + list.filter { $0.isCompleted }
        reassignSortIndices(reordered)
        withAnimation(.default) {
            saveCoreDataLocallyOnly()
        }
    }

    private func deleteRow(rowID: UUID, section: PackingChecklistSection) {
        invalidateDebouncedLocalSaveTask()
        var list = rows(in: section)
        guard let idx = list.firstIndex(where: { $0.id == rowID }) else { return }
        let doomed = list[idx]
        if let remoteId = doomed.id {
            SyncService.shared.deletePackingChecklistItemFromSupabase(checklistRowId: remoteId)
        }
        list.remove(at: idx)
        viewContext.delete(doomed)
        if list.isEmpty {
            ensureSeedRowIfNeeded(section: section)
            list = rows(in: section)
        } else {
            reassignSortIndices(list)
        }

        let focusIdx = min(idx, list.count - 1)
        let focusID = list[focusIdx].id
        saveCoreDataLocallyOnly()
        DispatchQueue.main.async {
            focusedRowID = focusID
        }
    }
}

#Preview {
    let pc = PersistenceController.preview
    let ctx = pc.container.viewContext
    let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
    request.fetchLimit = 1
    let wardrobe = (try? ctx.fetch(request))?.first ?? Wardrobe(context: ctx)
    return PackingChecklistView(selectedWardrobe: wardrobe)
        .environment(\.managedObjectContext, ctx)
        .environmentObject(AuthSession())
}
