//
//  HowToOnboardingView.swift
//  closet
//
//  Reusable how-to carousel (Profile tips + post-registration onboarding).
//

import SwiftUI
import UIKit

// MARK: - Page model

struct HowToWelcomeContent {
    /// First line, e.g. "Welcome to Redress," when a name is shown on the next line.
    let welcomeLine: String
    /// Second line; nil when display name is unavailable.
    let userName: String?
    let sections: [HowToWelcomeSection]
    let featureInviteSection: HowToWelcomeIconSection?
    let swipeToExploreMessage: String
    let footnote: String

    static func testFlightWelcome(displayName: String?) -> HowToWelcomeContent {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? nil : trimmed
        return HowToWelcomeContent(
            welcomeLine: name == nil ? "Welcome to Redress" : "Welcome to Redress,",
            userName: name,
            sections: [
                HowToWelcomeSection(
                    heading: "Beta version includes:",
                    items: [
                        "Unlimited closet uploads",
                        "Unlimited outfit collages",
                        "Unlimited calendar events",
                    ]
                ),
            ],
            featureInviteSection: HowToWelcomeIconSection(
                heading: "Features you are invited to test:",
                items: [
                    HowToWelcomeIconItem(text: "Closet Organizer", systemImage: "tshirt"),
                    HowToWelcomeIconItem(text: "Outfit Canvas", systemImage: "square.grid.3x3.fill"),
                    HowToWelcomeIconItem(text: "Travel Packing", systemImage: "airplane.circle"),
                    HowToWelcomeIconItem(text: "Calendar Events", systemImage: "calendar"),
                ]
            ),
            swipeToExploreMessage: "Swipe to explore features.",
            footnote: "Note: TestFlight beta builds automatically expire after 90 days. Data is device-local for this beta. Once the App Store version is available, install it to continue using the app."
        )
    }
}

struct HowToWelcomeSection {
    let heading: String
    let items: [String]
}

struct HowToWelcomeIconSection {
    let heading: String
    let items: [HowToWelcomeIconItem]
}

struct HowToWelcomeIconItem {
    let text: String
    let systemImage: String
}

enum HowToPage: Identifiable {
    case welcome(HowToWelcomeContent)
    case feature(HowToFeatureTip)

    var id: Int {
        switch self {
        case .welcome: 0
        case .feature(let tip): tip.id + 1
        }
    }

    static func testFlightPages(displayName: String?) -> [HowToPage] {
        [
            .welcome(.testFlightWelcome(displayName: displayName)),
        ] + HowToFeatureTip.testFlightTips.map { .feature($0) }
    }
}

struct HowToFeatureTip: Identifiable {
    let id: Int
    /// Bundle resource name without extension (PNG in Copy Bundle Resources).
    let imageName: String
    let title: String
    let message: String

    static let testFlightTips: [HowToFeatureTip] = [
        HowToFeatureTip(
            id: 0,
            imageName: "AddClosetItems",
            title: "Add Closet Items",
            message: "On the Closet tab, tap the + button in the top-right corner to add photos of your clothes."
        ),
        HowToFeatureTip(
            id: 1,
            imageName: "AddClosetOutfits",
            title: "Create Outfits",
            message: "Swipe to the Outfits tab on your closet, then tap + to build an outfit from your items."
        ),
        HowToFeatureTip(
            id: 2,
            imageName: "PackForTrips",
            title: "Pack For Trips",
            message: "Tap the airplane button at the top of the Closet tab to pack for your upcoming trips."
        ),
        HowToFeatureTip(
            id: 3,
            imageName: "AddNewWardrobe",
            title: "Add Multiple Wardrobes",
            message: "Tap the closet name at the top of the Closet tab to open your wardrobes and tap + to add a closet."
        ),
        HowToFeatureTip(
            id: 4,
            imageName: "PlanForEvents",
            title: "Plan Outfits For Events",
            message: "Open the Calendar tab to create an event, then add items and outfits to it from the event details."
        ),
    ]
}

/// Backward-compatible alias for feature tips only.
typealias ProfileHowToTip = HowToFeatureTip

// MARK: - Carousel (Profile embed)

struct HowToTipsCarousel: View {
    @Binding var currentPage: Int
    let pages: [HowToPage]
    var showsPageIndicator: Bool = true

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    HowToPageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if showsPageIndicator {
                HowToPageIndicator(currentPage: currentPage, pageCount: pages.count)
            }
        }
    }
}

struct HowToPageIndicator: View {
    let currentPage: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< pageCount, id: \.self) { index in
                Circle()
                    .fill(currentPage == index ? Color.blue : Color.blue.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tip \(currentPage + 1) of \(pageCount)")
    }
}

struct HowToPageView: View {
    let page: HowToPage

    var body: some View {
        switch page {
        case .welcome(let content):
            HowToWelcomePageView(content: content)
        case .feature(let tip):
            HowToFeatureTipPageView(tip: tip)
        }
    }
}

struct HowToWelcomePageView: View {
    @Environment(\.appCapabilities) private var appCapabilities
    let content: HowToWelcomeContent

    var body: some View {
        VStack(spacing: 16) {
            if appCapabilities.tier == .testflight {
                Text("Beta Version 1.0")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.top)
            }

            AuthAppIconView()
                .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text(content.welcomeLine)
                if let userName = content.userName {
                    Text(userName)
                }
            }
            .font(.title3)
            .fontWeight(.semibold)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.bottom)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(welcomeAccessibilityLabel)
            
            
            centeredWelcomeBody
               // .padding(.top)

            Spacer()
            
            Text(content.footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
    }

    private var welcomeAccessibilityLabel: String {
        if let userName = content.userName {
            return "\(content.welcomeLine) \(userName)"
        }
        return content.welcomeLine
    }

    /// Checklist + swipe hint as one leading-aligned block, centered on screen.
    private var centeredWelcomeBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(content.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.heading)
                        .font(.headline)
                        .fontWeight(.semibold)

                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        HowToWelcomeChecklistRow(text: item)
                    }
                }
            }

            if let invite = content.featureInviteSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text(invite.heading)
                        .font(.headline)
                        .fontWeight(.semibold)

                    ForEach(Array(invite.items.enumerated()), id: \.offset) { _, item in
                        HowToWelcomeIconRow(text: item.text, systemImage: item.systemImage)
                    }
                }
            }

            HStack(spacing: 6) {
                Text(content.swipeToExploreMessage)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)

                Image(systemName: "arrow.right")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
            //.padding(.bottom, 30)
            
            
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct HowToWelcomeChecklistRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.green)
                .frame(width: 22, alignment: .leading)
                .padding(.top, 2)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct HowToWelcomeIconRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.teal)
                .frame(width: 22, alignment: .leading)
                .padding(.top, 2)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct HowToFeatureTipPageView: View {
    let tip: HowToFeatureTip

    var body: some View {
        VStack(spacing: 12) {
            Text(tip.title)
                .font(.headline)
                .foregroundStyle(.teal)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(tip.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HowToTipImage(name: tip.imageName)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HowToTipImage: View {
    let name: String

    var body: some View {
        if let uiImage = UIImage(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 800)
                .accessibilityHidden(true)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray6), lineWidth: 2)
                )
        }
    }
}

// MARK: - Full-screen onboarding

struct HowToOnboardingView: View {
    /// When true, finishing the last step calls `HowToOnboardingStore.markCompleted`.
    var marksCompleteOnFinish: Bool = true
    var onComplete: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession
    @State private var currentPage = 0

    private var pages: [HowToPage] {
        HowToPage.testFlightPages(displayName: resolvedDisplayName)
    }

    private var resolvedDisplayName: String? {
        guard let userId = authSession.userId else { return nil }
        return UserProfileRepository(context: viewContext)
            .fetchProfile(userId: userId.uuidString)?
            .displayName
    }

    private var isLastPage: Bool {
        currentPage >= pages.count - 1
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HowToTipsCarousel(
                    currentPage: $currentPage,
                    pages: pages,
                    showsPageIndicator: true
                )
                .padding(.top, 40)

                primaryActionButton
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            .padding()
            .interactiveDismissDisabled(marksCompleteOnFinish)
        }
    }

    private var primaryActionButton: some View {
        Button {
            advanceOrFinish()
        } label: {
            Text(isLastPage ? "Get Started" : "Next")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Color.teal.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func advanceOrFinish() {
        if isLastPage {
            if marksCompleteOnFinish, let userId = authSession.userId {
                HowToOnboardingStore.markCompleted(userId: userId)
            }
            onComplete()
        } else {
            withAnimation {
                currentPage += 1
            }
        }
    }
}
