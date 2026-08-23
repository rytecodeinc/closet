//
//  PackingChecklistView.swift
//  closet
//
//  Notes-like packing checklist: one document per wardrobe + tab (Items / Tasks).
//  Syncs the whole document once on disappear (last-write-wins).
//

import SwiftUI
import CoreData
import UIKit

struct PackingChecklistView: View {
    @ObservedObject var selectedWardrobe: Wardrobe
    @ObservedObject var tabBarHideState: TabBarHideState
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = "Items"
    @State private var blocks: [PackingChecklistBlock] = []
    @State private var focusedBlockID: UUID?
    @State private var documentObjectID: NSManagedObjectID?
    @State private var showNewSectionAlert = false
    @State private var newSectionName = ""
    @State private var isDirty = false

    private var currentKind: PackingChecklistDocKind {
        PackingChecklistDocKind.fromSegment(selectedTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            checklistPickerBand

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(blocks) { block in
                        blockRow(block)
                            .id(block.id)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedBlockID = nil
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(UIColor.systemBackground))
        .navigationTitle("Checklist")
        .navigationBarTitleDisplayMode(.inline)
        .disableInteractivePopGesture()
        // Always hide — parent `.toolbar(.hidden)` alone can flicker on push/pop
        // (same pattern as Pack / read-only detail).
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newSectionName = ""
                        showNewSectionAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add section")
            }
        }
        .onAppear {
            tabBarHideState.shouldHideTabBar = true
            loadDocument(for: currentKind, preferFocus: false)
        }
        .onDisappear {
            persistAndSyncCurrentDocument()
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            persistLocalDocument(for: PackingChecklistDocKind.fromSegment(oldTab))
            loadDocument(for: PackingChecklistDocKind.fromSegment(newTab), preferFocus: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                persistAndSyncCurrentDocument()
            }
        }
        .alert("New Section", isPresented: $showNewSectionAlert) {
            TextField("Section name", text: $newSectionName)
                .textInputAutocapitalization(.words)
            Button("Add") {
                addSection(named: newSectionName)
                newSectionName = ""
            }
            Button("Cancel", role: .cancel) {
                newSectionName = ""
            }
        } message: {
            Text("Enter a name for the new section in the \(selectedTab) checklist.")
        }
    }

    private var checklistPickerBand: some View {
        Picker("", selection: $selectedTab) {
            Text("Items").tag("Items")
            Text("Tasks").tag("Tasks")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Rows

    @ViewBuilder
    private func blockRow(_ block: PackingChecklistBlock) -> some View {
        switch block {
        case .section(let id, let title):
            PackingChecklistBlockField(
                text: sectionTitleBinding(id: id, title: title),
                isFocused: focusedBlockID == id,
                font: UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold),
                textColor: .secondaryLabel,
                strikethrough: false,
                onSubmit: { insertItem(after: id) },
                onBackspaceWhenEmpty: { deleteBlockIfAllowed(id: id) },
                onBecameFocused: { focusedBlockID = id },
                onTextChanged: { markDirty() },
                onDismissKeyboard: { focusedBlockID = nil }
            )
            .frame(minHeight: 28)
            .textCase(nil)

        case .item(let id, let text, let checked):
            HStack(alignment: .center, spacing: 12) {
                Button {
                    toggleChecked(id: id)
                } label: {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(checked ? "Mark incomplete" : "Mark complete")

                PackingChecklistBlockField(
                    text: itemTextBinding(id: id, text: text),
                    isFocused: focusedBlockID == id,
                    font: .preferredFont(forTextStyle: .body),
                    textColor: checked ? .secondaryLabel : .label,
                    strikethrough: checked,
                    onSubmit: { insertItem(after: id) },
                    onBackspaceWhenEmpty: { deleteBlockIfAllowed(id: id) },
                    onBecameFocused: { focusedBlockID = id },
                    onTextChanged: { markDirty() },
                    onDismissKeyboard: { focusedBlockID = nil }
                )
                .frame(minHeight: 28)
            }
            .opacity(checked ? 0.75 : 1)
        }
    }

    private func sectionTitleBinding(id: UUID, title: String) -> Binding<String> {
        Binding(
            get: {
                if case .section(_, let t) = blocks.first(where: { $0.id == id }) {
                    return t
                }
                return title
            },
            set: { newValue in
                guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
                blocks[idx] = .section(id: id, title: newValue)
            }
        )
    }

    private func itemTextBinding(id: UUID, text: String) -> Binding<String> {
        Binding(
            get: {
                if case .item(_, let t, _) = blocks.first(where: { $0.id == id }) {
                    return t
                }
                return text
            },
            set: { newValue in
                guard let idx = blocks.firstIndex(where: { $0.id == id }),
                      case .item(_, _, let checked) = blocks[idx] else { return }
                blocks[idx] = .item(id: id, text: newValue, checked: checked)
            }
        )
    }

    // MARK: - Mutations

    private func markDirty() {
        isDirty = true
    }

    private func toggleChecked(id: UUID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }),
              case .item(_, let text, let checked) = blocks[idx] else { return }
        blocks[idx] = .item(id: id, text: text, checked: !checked)
        markDirty()
    }

    private func insertItem(after blockID: UUID) {
        guard let idx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let newID = UUID()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            blocks.insert(.item(id: newID, text: "", checked: false), at: idx + 1)
            // Hand focus to the new field without clearing first (avoids keyboard drop).
            focusedBlockID = newID
        }
        markDirty()
    }

    private func deleteBlockIfAllowed(id: UUID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        let block = blocks[idx]

        // Keep at least one item in the document.
        let itemCount = blocks.filter(\.isItem).count
        if case .item = block, itemCount <= 1 {
            blocks[idx] = .item(id: id, text: "", checked: false)
            focusedBlockID = id
            markDirty()
            return
        }

        // Don't delete the only section if it still has following content structure needs —
        // allow deleting empty section headers when not the sole remaining block.
        if case .section = block, blocks.count <= 1 {
            return
        }

        // Notes-like: hand focus to the previous (else next) field while this row still exists,
        // then remove — destroying the first-responder field first drops the keyboard.
        let handoffID: UUID? = {
            if idx > 0 { return blocks[idx - 1].id }
            if idx + 1 < blocks.count { return blocks[idx + 1].id }
            return nil
        }()

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let handoffID {
                focusedBlockID = handoffID
            }
        }

        DispatchQueue.main.async {
            guard let removeIdx = blocks.firstIndex(where: { $0.id == id }) else { return }
            var removeTransaction = Transaction(animation: nil)
            removeTransaction.disablesAnimations = true
            withTransaction(removeTransaction) {
                blocks.remove(at: removeIdx)
                if blocks.isEmpty {
                    blocks = PackingChecklistDocumentBody.emptySeed.blocks
                }
                if let handoffID, blocks.contains(where: { $0.id == handoffID }) {
                    focusedBlockID = handoffID
                } else if let first = blocks.first?.id {
                    focusedBlockID = first
                }
            }
            markDirty()
        }
    }

    private func addSection(named raw: String) {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let sectionID = UUID()
        let itemID = UUID()
        blocks.append(.section(id: sectionID, title: title))
        blocks.append(.item(id: itemID, text: "", checked: false))
        focusedBlockID = itemID
        markDirty()
    }

    // MARK: - Load / save / sync

    private func loadDocument(for kind: PackingChecklistDocKind, preferFocus: Bool) {
        focusedBlockID = nil
        let doc = fetchOrCreateDocument(kind: kind)
        documentObjectID = doc.objectID

        if let body = PackingChecklistDocumentCodec.decode(doc.bodyJSON), !body.blocks.isEmpty {
            blocks = body.blocks
        } else if let migrated = migrateLegacyDocument(kind: kind) {
            blocks = migrated.blocks
            saveBody(migrated, into: doc)
        } else {
            let seed = PackingChecklistDocumentBody.emptySeed
            blocks = seed.blocks
            saveBody(seed, into: doc)
        }
        isDirty = false
        if preferFocus, let first = blocks.first?.id {
            DispatchQueue.main.async { focusedBlockID = first }
        }
    }

    private func fetchOrCreateDocument(kind: PackingChecklistDocKind) -> PackingChecklistDocument {
        let request: NSFetchRequest<PackingChecklistDocument> = PackingChecklistDocument.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "wardrobe == %@ AND kind == %d",
            selectedWardrobe,
            kind.rawValue
        )
        if let existing = try? viewContext.fetch(request).first {
            return existing
        }

        let doc = PackingChecklistDocument(context: viewContext)
        doc.id = UUID()
        doc.kind = kind.rawValue
        doc.wardrobe = selectedWardrobe
        doc.createdAt = Date()
        doc.updatedAt = Date()
        if let uid = authSession.userId?.uuidString {
            doc.userId = uid
        }
        try? viewContext.save()
        return doc
    }

    private func saveBody(_ body: PackingChecklistDocumentBody, into doc: PackingChecklistDocument) {
        doc.bodyJSON = PackingChecklistDocumentCodec.encode(body)
        doc.updatedAt = Date()
        if doc.userId == nil || doc.userId?.isEmpty == true,
           let uid = authSession.userId?.uuidString {
            doc.userId = uid
        }
        try? viewContext.save()
    }

    private func persistLocalDocument(for kind: PackingChecklistDocKind) {
        let body = PackingChecklistDocumentBody(blocks: blocks)
        let doc: PackingChecklistDocument
        if let oid = documentObjectID,
           let existing = try? viewContext.existingObject(with: oid) as? PackingChecklistDocument,
           existing.kind == kind.rawValue {
            doc = existing
        } else {
            doc = fetchOrCreateDocument(kind: kind)
            documentObjectID = doc.objectID
        }
        saveBody(body, into: doc)
        isDirty = false
    }

    private func persistAndSyncCurrentDocument() {
        persistLocalDocument(for: currentKind)
        guard let oid = documentObjectID else { return }
        SyncService.shared.syncPackingChecklistDocumentIfNeeded(objectID: oid)
    }

    /// One-time lift from legacy section/item rows into a document body.
    private func migrateLegacyDocument(kind: PackingChecklistDocKind) -> PackingChecklistDocumentBody? {
        let sectionReq: NSFetchRequest<PackingChecklistSection> = PackingChecklistSection.fetchRequest()
        sectionReq.predicate = NSPredicate(
            format: "wardrobe == %@ AND kind == %d",
            selectedWardrobe,
            kind.rawValue
        )
        sectionReq.sortDescriptors = [NSSortDescriptor(keyPath: \PackingChecklistSection.sortIndex, ascending: true)]
        guard let sections = try? viewContext.fetch(sectionReq), !sections.isEmpty else { return nil }

        var blocks: [PackingChecklistBlock] = []
        for section in sections {
            let title = (section.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            blocks.append(.section(id: section.id ?? UUID(), title: title.isEmpty ? "General" : title))
            let items = ((section.items as? Set<PackingChecklistItem>) ?? [])
                .sorted { $0.sortIndex < $1.sortIndex }
            if items.isEmpty {
                blocks.append(.item(id: UUID(), text: "", checked: false))
            } else {
                for item in items {
                    blocks.append(.item(
                        id: item.id ?? UUID(),
                        text: item.text ?? "",
                        checked: item.isCompleted
                    ))
                }
            }
        }
        return PackingChecklistDocumentBody(blocks: blocks)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let wardrobe = Wardrobe(context: context)
    wardrobe.id = UUID()
    wardrobe.name = "Preview Closet"
    wardrobe.type = "closet"
    return NavigationStack {
        PackingChecklistView(
            selectedWardrobe: wardrobe,
            tabBarHideState: TabBarHideState()
        )
            .environment(\.managedObjectContext, context)
    }
}
