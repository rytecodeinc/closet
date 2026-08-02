//
//  CategoryVisibilityView.swift
//  closet
//

import SwiftUI
import CoreData
import Foundation

struct CategoryVisibilityView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @FetchRequest private var allCategories: FetchedResults<Category>

    /// Draft category visibility by lowercased name.
    @State private var categoryDrafts: [String: Bool] = [:]
    /// Draft subcategory visibility by "parent\u{1f}sub" lowercased keys.
    @State private var subcategoryDrafts: [String: Bool] = [:]
    @State private var showDiscardAlert = false

    init() {
        _allCategories = FetchRequest(
            entity: Category.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)],
            predicate: NSPredicate(value: false)
        )
    }

    private var uniqueCategories: [Category] {
        guard let uid = authSession.userId?.uuidString else { return [] }
        return dedupeNamedReferenceRows(Array(allCategories), preferredUserId: uid)
    }

    private var hasUnsavedChanges: Bool {
        for category in uniqueCategories {
            let catKey = draftKey(category.name)
            if draftCategoryValue(for: catKey, fallback: category.isVisible) != category.isVisible {
                return true
            }
            for sub in subcategories(for: category) {
                let subKey = subcategoryDraftKey(parent: category.name, sub: sub.name)
                if draftSubcategoryValue(for: subKey, fallback: sub.isVisible) != sub.isVisible {
                    return true
                }
            }
        }
        return false
    }

    var body: some View {
        List {
            ForEach(uniqueCategories, id: \.objectID) { category in
                let catKey = draftKey(category.name)
                let categoryVisible = draftCategoryValue(for: catKey, fallback: category.isVisible)

                Toggle(isOn: Binding(
                    get: { categoryVisible },
                    set: { setCategoryDraft($0, for: category) }
                )) {
                    Text(category.name ?? "")
                        .foregroundColor(.black)
                }

                ForEach(subcategories(for: category), id: \.objectID) { subcategory in
                    let subKey = subcategoryDraftKey(parent: category.name, sub: subcategory.name)
                    Toggle(isOn: Binding(
                        get: {
                            categoryVisible
                                && draftSubcategoryValue(for: subKey, fallback: subcategory.isVisible)
                        },
                        set: { subcategoryDrafts[subKey] = $0 }
                    )) {
                        Text(subcategory.name ?? "")
                            .foregroundColor(.black)
                            .padding(.leading, 20)
                    }
                    .disabled(!categoryVisible)
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .disableInteractivePopGesture()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    attemptDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveDrafts()
                }
                .disabled(!hasUnsavedChanges)
            }
        }
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved edits. Going back will discard them.")
        }
        .onAppear {
            ensureVisibleDefaults()
            refreshFetchPredicate()
            reloadDraftsFromStore()
        }
        .onChange(of: authSession.userId) { _, _ in
            ensureVisibleDefaults()
            refreshFetchPredicate()
            reloadDraftsFromStore()
        }
        .onChange(of: uniqueCategories.count) { _, _ in
            if categoryDrafts.isEmpty {
                reloadDraftsFromStore()
            }
        }
    }

    private func subcategories(for category: Category) -> [Subcategory] {
        guard let uid = authSession.userId?.uuidString else { return [] }
        let owned = ((category.subcategories as? Set<Subcategory>) ?? []).filter { $0.userId == uid }
        return dedupeNamedReferenceRows(Array(owned), preferredUserId: uid).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
        }
    }

    private func draftKey(_ name: String?) -> String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func subcategoryDraftKey(parent: String?, sub: String?) -> String {
        draftKey(parent) + "\u{1f}" + draftKey(sub)
    }

    private func draftCategoryValue(for key: String, fallback: Bool) -> Bool {
        categoryDrafts[key] ?? fallback
    }

    private func draftSubcategoryValue(for key: String, fallback: Bool) -> Bool {
        subcategoryDrafts[key] ?? fallback
    }

    private func setCategoryDraft(_ isVisible: Bool, for category: Category) {
        let catKey = draftKey(category.name)
        categoryDrafts[catKey] = isVisible
        if !isVisible {
            for sub in subcategories(for: category) {
                subcategoryDrafts[subcategoryDraftKey(parent: category.name, sub: sub.name)] = false
            }
        }
    }

    private func attemptDismiss() {
        if hasUnsavedChanges {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }

    private func reloadDraftsFromStore() {
        var cats: [String: Bool] = [:]
        var subs: [String: Bool] = [:]
        for category in uniqueCategories {
            let catKey = draftKey(category.name)
            guard !catKey.isEmpty else { continue }
            cats[catKey] = category.isVisible
            for sub in subcategories(for: category) {
                let subKey = subcategoryDraftKey(parent: category.name, sub: sub.name)
                guard !draftKey(sub.name).isEmpty else { continue }
                subs[subKey] = sub.isVisible
            }
        }
        categoryDrafts = cats
        subcategoryDrafts = subs
    }

    private func saveDrafts() {
        guard let uid = authSession.userId?.uuidString else { return }
        let now = Date()
        do {
            for category in uniqueCategories {
                let catKey = draftKey(category.name)
                guard !catKey.isEmpty else { continue }
                let desiredCategory = draftCategoryValue(for: catKey, fallback: category.isVisible)

                let catRequest: NSFetchRequest<Category> = Category.fetchRequest()
                catRequest.predicate = NSPredicate(
                    format: "name ==[c] %@ AND userId == %@",
                    category.name ?? "",
                    uid
                )
                let matches = try viewContext.fetch(catRequest)
                for match in matches {
                    match.isVisible = desiredCategory
                    match.updatedAt = now
                }

                for sub in subcategories(for: category) {
                    let subKey = subcategoryDraftKey(parent: category.name, sub: sub.name)
                    let desiredSub = desiredCategory
                        ? draftSubcategoryValue(for: subKey, fallback: sub.isVisible)
                        : false

                    let subRequest: NSFetchRequest<Subcategory> = Subcategory.fetchRequest()
                    subRequest.predicate = NSPredicate(
                        format: "name ==[c] %@ AND userId == %@ AND category.name ==[c] %@",
                        sub.name ?? "",
                        uid,
                        category.name ?? ""
                    )
                    for match in try viewContext.fetch(subRequest) {
                        match.isVisible = desiredSub
                        match.updatedAt = now
                    }
                    sub.isVisible = desiredSub
                    sub.updatedAt = now
                }
            }
            try viewContext.save()
            reloadDraftsFromStore()
        } catch {
            print("❌ Failed to save category visibility: \(error.localizedDescription)")
        }
    }

    /// Existing rows predating `isVisible` can land as `false` after migration; treat unset catalog as visible once.
    private func ensureVisibleDefaults() {
        guard let uid = authSession.userId?.uuidString else { return }
        let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
        categoryRequest.predicate = NSPredicate(format: "userId == %@", uid)
        let subcategoryRequest: NSFetchRequest<Subcategory> = Subcategory.fetchRequest()
        subcategoryRequest.predicate = NSPredicate(format: "userId == %@", uid)
        do {
            var changed = false
            for category in try viewContext.fetch(categoryRequest) {
                if !category.isVisible, category.updatedAt == nil {
                    category.isVisible = true
                    changed = true
                }
            }
            for subcategory in try viewContext.fetch(subcategoryRequest) {
                if !subcategory.isVisible, subcategory.updatedAt == nil {
                    subcategory.isVisible = true
                    changed = true
                }
            }
            if changed {
                try viewContext.save()
            }
        } catch {
            print("⚠️ Category visibility backfill failed: \(error.localizedDescription)")
        }
    }

    private func refreshFetchPredicate() {
        guard let uid = authSession.userId?.uuidString else {
            allCategories.nsPredicate = NSPredicate(value: false)
            return
        }
        allCategories.nsPredicate = NSPredicate(format: "userId == %@", uid)
    }
}
