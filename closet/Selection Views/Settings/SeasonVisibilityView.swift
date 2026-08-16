//
//  SeasonVisibilityView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import CoreData
import Foundation

struct SeasonVisibilityView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @FetchRequest private var allSeasons: FetchedResults<Season>

    /// Draft visibility by lowercased season name. Applied only on Save.
    @State private var drafts: [String: Bool] = [:]
    @State private var showDiscardAlert = false

    init() {
        _allSeasons = FetchRequest(
            entity: Season.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Season.name, ascending: true)],
            predicate: NSPredicate(value: false)
        )
    }

    private var uniqueSeasons: [Season] {
        guard let uid = authSession.userId?.uuidString else { return [] }
        return dedupeNamedReferenceRows(Array(allSeasons), preferredUserId: uid)
    }

    private var hasUnsavedChanges: Bool {
        for season in uniqueSeasons {
            let key = draftKey(season.name)
            if draftValue(for: key, fallback: season.isVisible) != season.isVisible {
                return true
            }
        }
        return false
    }

    var body: some View {
        List {
            ForEach(uniqueSeasons, id: \.objectID) { season in
                let key = draftKey(season.name)
                Toggle(isOn: Binding(
                    get: { draftValue(for: key, fallback: season.isVisible) },
                    set: { drafts[key] = $0 }
                )) {
                    Text(season.name ?? "")
                        .foregroundColor(.black)
                }
            }
        }
        .navigationTitle("Seasons")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
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
            consolidateIfNeeded()
            refreshFetchPredicate()
            reloadDraftsFromStore()
        }
        .onChange(of: authSession.userId) { _, _ in
            consolidateIfNeeded()
            refreshFetchPredicate()
            reloadDraftsFromStore()
        }
        .onChange(of: uniqueSeasons.count) { _, _ in
            if drafts.isEmpty {
                reloadDraftsFromStore()
            }
        }
    }

    private func draftKey(_ name: String?) -> String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func draftValue(for key: String, fallback: Bool) -> Bool {
        drafts[key] ?? fallback
    }

    private func attemptDismiss() {
        if hasUnsavedChanges {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }

    private func reloadDraftsFromStore() {
        var next: [String: Bool] = [:]
        for season in uniqueSeasons {
            let key = draftKey(season.name)
            guard !key.isEmpty else { continue }
            next[key] = season.isVisible
        }
        drafts = next
    }

    private func saveDrafts() {
        guard let uid = authSession.userId?.uuidString else { return }
        let now = Date()
        do {
            for season in uniqueSeasons {
                let key = draftKey(season.name)
                guard !key.isEmpty, let desired = drafts[key] else { continue }
                let request: NSFetchRequest<Season> = Season.fetchRequest()
                request.predicate = NSPredicate(
                    format: "name ==[c] %@ AND userId == %@",
                    season.name ?? "",
                    uid
                )
                for match in try viewContext.fetch(request) {
                    match.isVisible = desired
                    match.updatedAt = now
                }
            }
            try viewContext.save()
            reloadDraftsFromStore()
        } catch {
            print("❌ Failed to save season visibility: \(error.localizedDescription)")
        }
    }

    private func consolidateIfNeeded() {
        guard let userId = authSession.userId else { return }
        do {
            try ReferenceDataBootstrap.consolidateDuplicateColorsAndSeasons(for: userId, in: viewContext)
        } catch {
            print("⚠️ Season catalog consolidate failed: \(error.localizedDescription)")
        }
    }

    private func refreshFetchPredicate() {
        guard let uid = authSession.userId?.uuidString else {
            allSeasons.nsPredicate = NSPredicate(value: false)
            return
        }
        allSeasons.nsPredicate = NSPredicate(format: "userId == %@", uid)
    }
}
