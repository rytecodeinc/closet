//
//  ColorVisibilityView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import CoreData
import Foundation

struct ColorVisibilityView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @FetchRequest private var allColors: FetchedResults<AppColor>

    /// Draft visibility by lowercased color name. Applied only on Save.
    @State private var drafts: [String: Bool] = [:]
    @State private var showDiscardAlert = false

    init() {
        _allColors = FetchRequest(
            entity: AppColor.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \AppColor.name, ascending: true)],
            predicate: NSPredicate(value: false)
        )
    }

    private var uniqueColors: [AppColor] {
        guard let uid = authSession.userId?.uuidString else { return [] }
        return dedupeNamedReferenceRows(Array(allColors), preferredUserId: uid)
    }

    private var hasUnsavedChanges: Bool {
        for color in uniqueColors {
            let key = draftKey(color.name)
            if draftValue(for: key, fallback: color.isVisible) != color.isVisible {
                return true
            }
        }
        return false
    }

    var body: some View {
        List {
            ForEach(uniqueColors, id: \.objectID) { color in
                let key = draftKey(color.name)
                Toggle(isOn: Binding(
                    get: { draftValue(for: key, fallback: color.isVisible) },
                    set: { drafts[key] = $0 }
                )) {
                    HStack {
                        Circle()
                            .fill(colorFromName(color.name ?? ""))
                            .frame(width: 24, height: 24)
                        Text(color.name ?? "")
                            .foregroundColor(.black)
                    }
                }
            }
        }
        .navigationTitle("Colors")
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
            consolidateIfNeeded()
            refreshFetchPredicate()
            reloadDraftsFromStore()
        }
        .onChange(of: authSession.userId) { _, _ in
            consolidateIfNeeded()
            refreshFetchPredicate()
            reloadDraftsFromStore()
        }
        .onChange(of: uniqueColors.count) { _, _ in
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
        for color in uniqueColors {
            let key = draftKey(color.name)
            guard !key.isEmpty else { continue }
            next[key] = color.isVisible
        }
        drafts = next
    }

    private func saveDrafts() {
        guard let uid = authSession.userId?.uuidString else { return }
        let now = Date()
        do {
            for color in uniqueColors {
                let key = draftKey(color.name)
                guard !key.isEmpty, let desired = drafts[key] else { continue }
                let request: NSFetchRequest<AppColor> = AppColor.fetchRequest()
                request.predicate = NSPredicate(
                    format: "name ==[c] %@ AND userId == %@",
                    color.name ?? "",
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
            print("❌ Failed to save color visibility: \(error.localizedDescription)")
        }
    }

    private func consolidateIfNeeded() {
        guard let userId = authSession.userId else { return }
        do {
            try ReferenceDataBootstrap.consolidateDuplicateColorsAndSeasons(for: userId, in: viewContext)
        } catch {
            print("⚠️ Color catalog consolidate failed: \(error.localizedDescription)")
        }
    }

    private func refreshFetchPredicate() {
        guard let uid = authSession.userId?.uuidString else {
            allColors.nsPredicate = NSPredicate(value: false)
            return
        }
        allColors.nsPredicate = NSPredicate(format: "userId == %@", uid)
    }
}
