//
//  CategoryOnboardingView.swift
//  closet
//
//  Shared step: choose which default categories to seed for this account.
//

import SwiftUI
import CoreData

struct CategoryOnboardingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession

    @Binding var selectedCategoryNames: Set<String>
    var showsHeader: Bool = true
    var onError: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeader {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose your categories")
                        .font(.headline)
                    Text("Turn off any you don't use. We'll add subcategories for each category you keep.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if selectedCategoryNames.isEmpty {
                Text("Select at least one category to continue.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            ForEach(ReferenceDataBootstrap.masterCategoryNames, id: \.self) { name in
                Toggle(isOn: categoryBinding(for: name)) {
                    Text(name)
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private func categoryBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { selectedCategoryNames.contains(name) },
            set: { isOn in
                if isOn {
                    selectedCategoryNames.insert(name)
                } else {
                    selectedCategoryNames.remove(name)
                }
            }
        )
    }

    /// Seeds selected categories + universal defaults and marks onboarding complete.
    static func completeOnboarding(
        selectedNames: Set<String>,
        userId: UUID,
        in context: NSManagedObjectContext
    ) throws {
        let ordered = ReferenceDataBootstrap.masterCategoryNames.filter { selectedNames.contains($0) }
        guard !ordered.isEmpty else {
            throw CategoryOnboardingError.noCategoriesSelected
        }
        try ReferenceDataBootstrap.seedSelectedCategories(ordered, for: userId, in: context)
        try ReferenceDataBootstrap.ensureUniversalDefaults(for: userId, in: context)
        CategoryOnboardingStore.markCompleted(userId: userId)
    }

    /// TestFlight: full master catalog + subcategories without a selection screen.
    static func completeOnboardingWithFullCatalog(
        userId: UUID,
        in context: NSManagedObjectContext
    ) throws {
        try completeOnboarding(
            selectedNames: Set(ReferenceDataBootstrap.masterCategoryNames),
            userId: userId,
            in: context
        )
    }
}

enum CategoryOnboardingError: LocalizedError {
    case noCategoriesSelected
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .noCategoriesSelected:
            return "Select at least one category to continue."
        case .notSignedIn:
            return "Sign in to save your category choices."
        }
    }
}
