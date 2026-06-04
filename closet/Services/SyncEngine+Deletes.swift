//
//  SyncEngine+Deletes.swift
//  closet
//

import Foundation

extension SyncEngine {

    /// Deletes a tag from Supabase (item_tags, outfit_tags, tags). Call after removing the tag from Core Data.
    func deleteTagFromSupabase(tagId: UUID) async {
        let supabase = await getSupabase()
        let isAuthenticated = await MainActor.run { supabase.isAuthenticated }
        guard isAuthenticated else { return }
        let idString = tagId.uuidString
        do {
            try await supabase.supabaseClient.from("item_tags")
                .delete()
                .eq("tag_id", value: idString)
                .execute()
            try await supabase.supabaseClient.from("outfit_tags")
                .delete()
                .eq("tag_id", value: idString)
                .execute()
            try await supabase.supabaseClient.from("tags")
                .delete()
                .eq("id", value: idString)
                .execute()
            print("✅ Deleted tag \(idString) from Supabase")
        } catch {
            print("⚠️ Failed to delete tag from Supabase: \(error.localizedDescription)")
        }
    }

    /// Deletes an outfit category from Supabase. Call after removing the category from Core Data.
    func deleteOutfitCategoryFromSupabase(categoryId: UUID) async {
        let supabase = await getSupabase()
        let isAuthenticated = await MainActor.run { supabase.isAuthenticated }
        guard isAuthenticated else { return }
        let idString = categoryId.uuidString
        do {
            try await supabase.supabaseClient.from("outfit_categories")
                .delete()
                .eq("id", value: idString)
                .execute()
            print("✅ Deleted outfit category \(idString) from Supabase")
        } catch {
            print("⚠️ Failed to delete outfit category from Supabase: \(error.localizedDescription)")
        }
    }

    /// Deletes a checklist row server-side after local removal.
    func deletePackingChecklistItemFromSupabase(checklistRowId: UUID) async {
        let supabase = await getSupabase()
        let isAuthenticated = await MainActor.run { supabase.isAuthenticated }
        guard isAuthenticated else { return }
        let idString = checklistRowId.uuidString
        do {
            try await supabase.supabaseClient.from("packing_checklist_items")
                .delete()
                .eq("id", value: idString)
                .execute()
            print("✅ Deleted packing_checklist_items row \(idString) from Supabase")
        } catch {
            print("⚠️ Failed to delete packing_checklist_items \(idString): \(error.localizedDescription)")
        }
    }
}
