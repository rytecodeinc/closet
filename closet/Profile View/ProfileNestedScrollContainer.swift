//
//  ProfileNestedScrollContainer.swift
//  closet
//
//  Instagram-style nested scroll: collapsing header, sticky chrome, horizontally
//  paged tabs each with their own vertical UIScrollView (scroll position preserved).
//

import SwiftUI
import UIKit

/// Hosts a collapsing header, sticky chrome, and a paged Items/Outfits region with
/// coordinated outer + per-tab scrolling.
struct ProfileNestedScrollContainer<Header: View, Sticky: View, Items: View, Outfits: View>: UIViewControllerRepresentable {
    @Binding var selectedTab: String
    let header: Header
    let sticky: Sticky
    let itemsPage: Items
    let outfitsPage: Outfits
    /// Pull-to-refresh at the top of the profile scroll (items / outfits reload).
    var onRefresh: (() async -> Void)?
    /// When true, header collapse snaps fully open or fully closed (no resting mid-collapse).
    var snapsHeaderCollapse: Bool = false
    /// Sticky search session — capture offsets on activate, restore on Cancel / dismiss.
    var searchSessionActive: Bool = false

    func makeUIViewController(context: Context) -> ProfileNestedScrollViewController {
        let vc = ProfileNestedScrollViewController()
        vc.selectedTab = selectedTab
        vc.onRefresh = onRefresh
        vc.snapsHeaderCollapse = snapsHeaderCollapse
        vc.onSelectedTabChange = { tab in
            if selectedTab != tab {
                selectedTab = tab
            }
        }
        vc.install(
            header: header,
            sticky: sticky,
            itemsPage: itemsPage,
            outfitsPage: outfitsPage
        )
        vc.applySearchSessionActive(searchSessionActive)
        return vc
    }

    func updateUIViewController(_ uiViewController: ProfileNestedScrollViewController, context: Context) {
        uiViewController.onRefresh = onRefresh
        uiViewController.snapsHeaderCollapse = snapsHeaderCollapse
        uiViewController.onSelectedTabChange = { tab in
            if selectedTab != tab {
                selectedTab = tab
            }
        }
        if uiViewController.selectedTab != selectedTab {
            uiViewController.setSelectedTab(selectedTab, animated: true)
        }
        // On search activate: capture offsets before sticky swaps / keyboard avoidance.
        // On dismiss: schedule restore after keyboard + chrome settle.
        let searchBecameActive = searchSessionActive && !uiViewController.isSearchSessionActiveForHost
        uiViewController.applySearchSessionActive(searchSessionActive)
        uiViewController.update(
            header: header,
            sticky: sticky,
            itemsPage: itemsPage,
            outfitsPage: outfitsPage
        )
        // If capture ran before child scroll views were discovered, refresh saved child offsets once.
        if searchBecameActive {
            uiViewController.refreshCapturedSearchChildOffsetsIfNeeded()
        }
    }
}

// MARK: - Hosting

/// Nested SwiftUI islands must not see the parent `UINavigationController`.
/// Plain `UIHostingController` syncs its (empty) `navigationItem` into that bar and
/// wipes Profile’s gear / edit / users toolbar on first appearance.
private final class NavigationIsolatedHostingController: UIHostingController<AnyView> {
    override var navigationController: UINavigationController? { nil }
}

// MARK: - View controller

final class ProfileNestedScrollViewController: UIViewController {
    var selectedTab: String = "Items"
    var onSelectedTabChange: ((String) -> Void)?
    var onRefresh: (() async -> Void)?
    /// Other-user profile: snap header like a vertical page (expanded ↔ collapsed only).
    var snapsHeaderCollapse: Bool = false

    private let outerScrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let headerContainer = UIView()
    private let stickyContainer = UIView()
    private let pagerContainer = UIView()
    private var pagerHeightConstraint: NSLayoutConstraint?
    private let refreshControl = UIRefreshControl()
    /// Allow enough overscroll for `UIRefreshControl` while nested scroll is coordinating.
    private let refreshOverscrollLimit: CGFloat = 140
    // TODO: Revisit pull-to-refresh — page-snap / threshold-commit (content pinned on half-pull, no spinner peek; engage only past commit threshold). See .cursor/rules/profile-pull-to-refresh-deferred.mdc.

    private var headerHost: NavigationIsolatedHostingController?
    private var stickyHost: NavigationIsolatedHostingController?
    private var itemsHost: NavigationIsolatedHostingController?
    private var outfitsHost: NavigationIsolatedHostingController?

    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: nil
    )
    private let itemsPageVC = UIViewController()
    private let outfitsPageVC = UIViewController()

    private weak var itemsScrollView: UIScrollView?
    private weak var outfitsScrollView: UIScrollView?

    private var headerHeight: CGFloat = 0
    private var stickyHeight: CGFloat = 0
    private var isUpdatingOffsets = false
    private var didScheduleScrollDiscovery = false
    private var isRefreshInFlight = false
    private var isHeaderSnapAnimating = false
    /// Velocity past this commits to the flicked page (points/sec).
    private let headerSnapVelocityThreshold: CGFloat = 0.35

    private var isSearchSessionActive = false
    /// Hosted representable reads this to detect rising-edge capture timing.
    var isSearchSessionActiveForHost: Bool { isSearchSessionActive }
    private var hasCapturedSearchScrollOffsets = false
    private var savedSearchOuterOffset: CGFloat?
    private var savedSearchItemsOffset: CGFloat?
    private var savedSearchOutfitsOffset: CGFloat?
    private var searchOffsetRestoreWorkItem: DispatchWorkItem?

    private var maxOuterOffset: CGFloat {
        max(0, headerHeight)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // Avoid UIPageViewController / nested scroll hosts suppressing the SwiftUI nav bar.
        edgesForExtendedLayout = [.bottom]
        extendedLayoutIncludesOpaqueBars = false

        outerScrollView.translatesAutoresizingMaskIntoConstraints = false
        outerScrollView.delegate = self
        outerScrollView.showsVerticalScrollIndicator = false
        outerScrollView.alwaysBounceVertical = true
        // Keep content below the navigation bar / Profile toolbar (safe-area pinned).
        outerScrollView.contentInsetAdjustmentBehavior = .never
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        outerScrollView.refreshControl = refreshControl
        view.addSubview(outerScrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        outerScrollView.addSubview(contentStack)

        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        stickyContainer.translatesAutoresizingMaskIntoConstraints = false
        pagerContainer.translatesAutoresizingMaskIntoConstraints = false
        pagerContainer.backgroundColor = .systemBackground

        contentStack.addArrangedSubview(headerContainer)
        contentStack.addArrangedSubview(stickyContainer)
        contentStack.addArrangedSubview(pagerContainer)

        let pagerHeight = pagerContainer.heightAnchor.constraint(
            equalTo: outerScrollView.frameLayoutGuide.heightAnchor
        )
        pagerHeightConstraint = pagerHeight

        NSLayoutConstraint.activate([
            outerScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            outerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.widthAnchor),

            pagerHeight
        ])

        addChild(pageViewController)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        pagerContainer.addSubview(pageViewController.view)
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: pagerContainer.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: pagerContainer.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: pagerContainer.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: pagerContainer.bottomAnchor)
        ])
        pageViewController.didMove(toParent: self)
        pageViewController.dataSource = self
        pageViewController.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ensureNavigationBarVisible(animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ensureNavigationBarVisible(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshMeasuredHeights()
        updatePagerHeightConstraint()
        discoverChildScrollViewsIfNeeded()
        applyOuterLockIfNeeded()
    }

    func install<Header: View, Sticky: View, Items: View, Outfits: View>(
        header: Header,
        sticky: Sticky,
        itemsPage: Items,
        outfitsPage: Outfits
    ) {
        embed(header: AnyView(header), sticky: AnyView(sticky), items: AnyView(itemsPage), outfits: AnyView(outfitsPage))
        setSelectedTab(selectedTab, animated: false)
        DispatchQueue.main.async { [weak self] in
            self?.ensureNavigationBarVisible(animated: false)
        }
    }

    func update<Header: View, Sticky: View, Items: View, Outfits: View>(
        header: Header,
        sticky: Sticky,
        itemsPage: Items,
        outfitsPage: Outfits
    ) {
        headerHost?.rootView = AnyView(header)
        stickyHost?.rootView = AnyView(sticky)
        itemsHost?.rootView = AnyView(itemsPage)
        outfitsHost?.rootView = AnyView(outfitsPage)
        view.setNeedsLayout()
    }

    func setSelectedTab(_ tab: String, animated: Bool) {
        let normalized = (tab == "Outfits") ? "Outfits" : "Items"
        selectedTab = normalized
        let target = normalized == "Outfits" ? outfitsPageVC : itemsPageVC
        let current = pageViewController.viewControllers?.first
        guard current !== target else {
            discoverChildScrollViewsIfNeeded()
            return
        }
        let direction: UIPageViewController.NavigationDirection =
            normalized == "Outfits" ? .forward : .reverse
        pageViewController.setViewControllers([target], direction: direction, animated: animated)
        // Force rediscovery after page change — SwiftUI scroll views attach asynchronously.
        itemsScrollView = nil
        outfitsScrollView = nil
        didScheduleScrollDiscovery = false
        discoverChildScrollViewsIfNeeded()
        ensureNavigationBarVisible(animated: false)
    }

    @objc private func handlePullToRefresh() {
        guard !isRefreshInFlight else { return }
        guard let onRefresh else {
            refreshControl.endRefreshing()
            return
        }
        isRefreshInFlight = true
        Task { @MainActor in
            await onRefresh()
            self.refreshControl.endRefreshing()
            self.isRefreshInFlight = false
        }
    }

    private func embed(header: AnyView, sticky: AnyView, items: AnyView, outfits: AnyView) {
        if headerHost == nil {
            let host = makeHost(rootView: header, backgroundColor: .clear)
            headerHost = host
            addHost(host, to: headerContainer)
        } else {
            headerHost?.rootView = header
        }

        if stickyHost == nil {
            let host = makeHost(rootView: sticky, backgroundColor: .systemBackground)
            stickyHost = host
            addHost(host, to: stickyContainer)
        } else {
            stickyHost?.rootView = sticky
        }

        if itemsHost == nil {
            let host = makeHost(rootView: items, backgroundColor: .systemBackground)
            itemsHost = host
            embedPageHost(host, in: itemsPageVC)
        } else {
            itemsHost?.rootView = items
        }

        if outfitsHost == nil {
            let host = makeHost(rootView: outfits, backgroundColor: .systemBackground)
            outfitsHost = host
            embedPageHost(host, in: outfitsPageVC)
        } else {
            outfitsHost?.rootView = outfits
        }
    }

    private func makeHost(rootView: AnyView, backgroundColor: UIColor) -> NavigationIsolatedHostingController {
        let host = NavigationIsolatedHostingController(rootView: rootView)
        host.view.backgroundColor = backgroundColor
        host.safeAreaRegions = []
        return host
    }

    private func addHost(_ host: NavigationIsolatedHostingController, to container: UIView) {
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func embedPageHost(_ host: NavigationIsolatedHostingController, in page: UIViewController) {
        page.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        page.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: page.view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: page.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: page.view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: page.view.bottomAnchor)
        ])
        host.didMove(toParent: page)
    }

    private func ensureNavigationBarVisible(animated: Bool) {
        var responder: UIViewController? = self
        while let current = responder {
            if let nav = current.navigationController {
                nav.setNavigationBarHidden(false, animated: animated)
                nav.navigationBar.isHidden = false
                break
            }
            responder = current.parent
        }
        // Also ask the nearest parent hosting controller’s nav stack (SwiftUI TabView).
        if let nav = nearestNavigationController() {
            nav.setNavigationBarHidden(false, animated: animated)
            nav.navigationBar.isHidden = false
        }
    }

    private func nearestNavigationController() -> UINavigationController? {
        var node: UIViewController? = self
        while let current = node {
            if let nav = current as? UINavigationController { return nav }
            if let nav = current.navigationController { return nav }
            node = current.parent ?? current.presentingViewController
        }
        var viewNode: UIView? = view.superview
        while let current = viewNode {
            if let responder = current.next as? UIViewController {
                if let nav = responder.navigationController { return nav }
            }
            viewNode = current.superview
        }
        return nil
    }

    private func refreshMeasuredHeights() {
        headerHost?.view.layoutIfNeeded()
        stickyHost?.view.layoutIfNeeded()
        let width = max(view.bounds.width, 1)
        let newHeader = headerHost?.view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height ?? headerContainer.bounds.height
        let newSticky = stickyHost?.view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height ?? stickyContainer.bounds.height
        if newHeader > 1 { headerHeight = newHeader }
        if newSticky > 1 { stickyHeight = newSticky }
    }

    private func updatePagerHeightConstraint() {
        // When header is collapsed, sticky sits at top; pager fills the rest of the viewport.
        guard let pagerHeightConstraint else { return }
        let constant = -stickyHeight
        if abs(pagerHeightConstraint.constant - constant) > 0.5 {
            pagerHeightConstraint.constant = constant
        }
    }

    private func discoverChildScrollViewsIfNeeded() {
        if itemsScrollView == nil, let view = itemsHost?.view {
            if let found = Self.findScrollView(in: view) {
                found.delegate = self
                found.showsVerticalScrollIndicator = false
                found.contentInsetAdjustmentBehavior = .never
                itemsScrollView = found
            }
        }
        if outfitsScrollView == nil, let view = outfitsHost?.view {
            if let found = Self.findScrollView(in: view) {
                found.delegate = self
                found.showsVerticalScrollIndicator = false
                found.contentInsetAdjustmentBehavior = .never
                outfitsScrollView = found
            }
        }

        if (itemsScrollView == nil || outfitsScrollView == nil), !didScheduleScrollDiscovery {
            didScheduleScrollDiscovery = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.didScheduleScrollDiscovery = false
                self.discoverChildScrollViewsIfNeeded()
            }
        }
    }

    private func applyOuterLockIfNeeded() {
        guard !isUpdatingOffsets else { return }
        let maxY = maxOuterOffset
        if outerScrollView.contentOffset.y > maxY {
            isUpdatingOffsets = true
            outerScrollView.contentOffset.y = maxY
            isUpdatingOffsets = false
        }
    }

    /// Skip no-op `contentOffset` writes — they fight the pan gesture and feel stepped on scroll-up.
    private func pinChildScrollToTopIfNeeded(_ scrollView: UIScrollView?) {
        guard let scrollView, abs(scrollView.contentOffset.y) > 0.5 else { return }
        isUpdatingOffsets = true
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: 0), animated: false)
        isUpdatingOffsets = false
    }

    /// Rising edge captures offsets before keyboard avoidance; falling edge restores after dismiss.
    func applySearchSessionActive(_ active: Bool) {
        if active, !isSearchSessionActive {
            isSearchSessionActive = true
            captureScrollOffsetsForSearch()
        } else if !active, isSearchSessionActive {
            isSearchSessionActive = false
            scheduleRestoreScrollOffsetsAfterSearch()
        }
    }

    private func captureScrollOffsetsForSearch() {
        searchOffsetRestoreWorkItem?.cancel()
        searchOffsetRestoreWorkItem = nil
        discoverChildScrollViewsIfNeeded()
        savedSearchOuterOffset = outerScrollView.contentOffset.y
        savedSearchItemsOffset = itemsScrollView?.contentOffset.y
        savedSearchOutfitsOffset = outfitsScrollView?.contentOffset.y
        hasCapturedSearchScrollOffsets = true
    }

    func refreshCapturedSearchChildOffsetsIfNeeded() {
        guard hasCapturedSearchScrollOffsets, isSearchSessionActive else { return }
        discoverChildScrollViewsIfNeeded()
        if savedSearchItemsOffset == nil, let y = itemsScrollView?.contentOffset.y {
            savedSearchItemsOffset = y
        }
        if savedSearchOutfitsOffset == nil, let y = outfitsScrollView?.contentOffset.y {
            savedSearchOutfitsOffset = y
        }
    }

    private func scheduleRestoreScrollOffsetsAfterSearch() {
        searchOffsetRestoreWorkItem?.cancel()
        // Wait for keyboard + sticky chrome layout to settle, then put scroll back.
        let work = DispatchWorkItem { [weak self] in
            self?.restoreScrollOffsetsAfterSearch()
        }
        searchOffsetRestoreWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func restoreScrollOffsetsAfterSearch() {
        guard hasCapturedSearchScrollOffsets else { return }
        discoverChildScrollViewsIfNeeded()
        isHeaderSnapAnimating = false

        let maxY = maxOuterOffset
        isUpdatingOffsets = true
        if let outer = savedSearchOuterOffset {
            let clamped = min(max(-refreshOverscrollLimit, outer), maxY)
            outerScrollView.setContentOffset(CGPoint(x: 0, y: clamped), animated: false)
        }
        if let itemsY = savedSearchItemsOffset, let itemsScrollView {
            itemsScrollView.setContentOffset(
                CGPoint(x: itemsScrollView.contentOffset.x, y: max(0, itemsY)),
                animated: false
            )
        }
        if let outfitsY = savedSearchOutfitsOffset, let outfitsScrollView {
            outfitsScrollView.setContentOffset(
                CGPoint(x: outfitsScrollView.contentOffset.x, y: max(0, outfitsY)),
                animated: false
            )
        }
        isUpdatingOffsets = false

        hasCapturedSearchScrollOffsets = false
        savedSearchOuterOffset = nil
        savedSearchItemsOffset = nil
        savedSearchOutfitsOffset = nil
        searchOffsetRestoreWorkItem = nil

        // Re-enable normal header page-snap settle after restore.
        settleNestedScrollOffsets()
    }

    /// Page-style header: only fully expanded (`0`) or fully collapsed (`maxY`).
    private func pageSnappedHeaderOffset(proposedY: CGFloat, velocityY: CGFloat, maxY: CGFloat) -> CGFloat {
        guard maxY > 1 else { return 0 }
        // Positive velocity → content moves up → collapse. Negative → expand.
        if velocityY > headerSnapVelocityThreshold { return maxY }
        if velocityY < -headerSnapVelocityThreshold { return 0 }
        return proposedY > maxY * 0.5 ? maxY : 0
    }

    private func animateOuterHeaderSnap(to y: CGFloat) {
        let maxY = maxOuterOffset
        let target = min(max(0, y), maxY)
        let current = outerScrollView.contentOffset.y
        guard abs(current - target) > 0.5 else {
            if target < maxY - 0.5 {
                pinChildScrollToTopIfNeeded(itemsScrollView)
                pinChildScrollToTopIfNeeded(outfitsScrollView)
            }
            return
        }
        isHeaderSnapAnimating = true
        isUpdatingOffsets = true
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.outerScrollView.contentOffset = CGPoint(x: 0, y: target)
        } completion: { _ in
            self.isUpdatingOffsets = false
            self.isHeaderSnapAnimating = false
            if target < self.maxOuterOffset - 0.5 {
                self.pinChildScrollToTopIfNeeded(self.itemsScrollView)
                self.pinChildScrollToTopIfNeeded(self.outfitsScrollView)
            }
        }
    }

    private static func findScrollView(in root: UIView) -> UIScrollView? {
        var candidate: UIScrollView?
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView {
                // Prefer the deepest vertical content scroll view.
                candidate = scroll
            }
            stack.append(contentsOf: view.subviews)
        }
        return candidate
    }
}

// MARK: - UIScrollViewDelegate

extension ProfileNestedScrollViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isUpdatingOffsets, !isHeaderSnapAnimating else { return }

        // Ignore UIPageViewController's horizontal scroll view.
        if let pageScroll = pageViewController.view.subviews.first(where: { $0 is UIScrollView }),
           scrollView === pageScroll {
            return
        }

        let maxY = maxOuterOffset

        if scrollView === outerScrollView {
            if scrollView.contentOffset.y > maxY + 0.5 {
                isUpdatingOffsets = true
                scrollView.contentOffset.y = maxY
                isUpdatingOffsets = false
            }

            // Only pin children that have drifted — avoid per-frame zeroing when already at top.
            if scrollView.contentOffset.y < maxY - 0.5 {
                pinChildScrollToTopIfNeeded(itemsScrollView)
                pinChildScrollToTopIfNeeded(outfitsScrollView)
            }
            return
        }

        // Child tab scroll views.
        let outerY = outerScrollView.contentOffset.y
        if outerY < maxY - 0.5 {
            let childY = scrollView.contentOffset.y
            // No movement to transfer — skip writes (main scroll-up stutter source).
            guard abs(childY) > 0.5 else { return }
            isUpdatingOffsets = true
            let proposed = outerY + childY
            // Allow negative outer offset so pull-to-refresh can engage at the top.
            outerScrollView.contentOffset.y = min(max(-refreshOverscrollLimit, proposed), maxY)
            if abs(scrollView.contentOffset.y) > 0.5 {
                scrollView.contentOffset.y = 0
            }
            isUpdatingOffsets = false
            return
        }

        // Header collapsed: expand only when the child pulls past its top.
        if scrollView.contentOffset.y < -0.5 {
            isUpdatingOffsets = true
            outerScrollView.contentOffset.y = max(-refreshOverscrollLimit, maxY + scrollView.contentOffset.y)
            scrollView.contentOffset.y = 0
            isUpdatingOffsets = false
        }
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard snapsHeaderCollapse, !isHeaderSnapAnimating else { return }

        // Ignore UIPageViewController's horizontal scroll view.
        if let pageScroll = pageViewController.view.subviews.first(where: { $0 is UIScrollView }),
           scrollView === pageScroll {
            return
        }

        let maxY = maxOuterOffset
        guard maxY > 1 else { return }

        if scrollView === outerScrollView {
            let proposed = targetContentOffset.pointee.y
            // Leave pull-to-refresh overscroll alone.
            if proposed < -0.5 || outerScrollView.contentOffset.y < -0.5 { return }
            if proposed >= maxY - 0.5 {
                targetContentOffset.pointee.y = maxY
                return
            }
            if proposed <= 0.5, outerScrollView.contentOffset.y <= 0.5 {
                targetContentOffset.pointee.y = 0
                return
            }
            // Mid-header — snap fully open or fully closed (ItemDetail front/worn page feel).
            let referenceY = min(max(max(proposed, outerScrollView.contentOffset.y), 0), maxY)
            targetContentOffset.pointee.y = pageSnappedHeaderOffset(
                proposedY: referenceY,
                velocityY: velocity.y,
                maxY: maxY
            )
            return
        }

        // Child drove header collapse/expand — snap outer; stop child mid-header settle.
        let outerY = outerScrollView.contentOffset.y
        let headerBetweenEnds = outerY > 0 && outerY < maxY
        let expandingViaChildPull = outerY >= maxY - 0.5 && scrollView.contentOffset.y < -0.5
        guard headerBetweenEnds || expandingViaChildPull else { return }

        let proposedOuter = expandingViaChildPull
            ? max(0, maxY + min(0, scrollView.contentOffset.y))
            : outerY
        let snap = pageSnappedHeaderOffset(proposedY: proposedOuter, velocityY: velocity.y, maxY: maxY)
        targetContentOffset.pointee.y = 0
        DispatchQueue.main.async { [weak self] in
            self?.animateOuterHeaderSnap(to: snap)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        settleNestedScrollOffsets()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settleNestedScrollOffsets()
    }

    /// One-shot sync after a gesture ends (instead of continuous dual-tab zeroing).
    private func settleNestedScrollOffsets() {
        guard !isUpdatingOffsets, !isHeaderSnapAnimating else { return }
        let maxY = maxOuterOffset
        if outerScrollView.contentOffset.y > maxY + 0.5 {
            isUpdatingOffsets = true
            outerScrollView.contentOffset.y = maxY
            isUpdatingOffsets = false
        }

        if snapsHeaderCollapse, maxY > 1 {
            let y = outerScrollView.contentOffset.y
            // Don't fight pull-to-refresh; snap any in-between header offset.
            if y >= 0, y > 0, y < maxY {
                let snap = pageSnappedHeaderOffset(proposedY: y, velocityY: 0, maxY: maxY)
                animateOuterHeaderSnap(to: snap)
                return
            }
        }

        if outerScrollView.contentOffset.y < maxY - 0.5 {
            pinChildScrollToTopIfNeeded(itemsScrollView)
            pinChildScrollToTopIfNeeded(outfitsScrollView)
        }
    }
}

// MARK: - UIPageViewController

extension ProfileNestedScrollViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        viewController === outfitsPageVC ? itemsPageVC : nil
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        viewController === itemsPageVC ? outfitsPageVC : nil
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed, let visible = pageViewController.viewControllers?.first else { return }
        let tab = (visible === outfitsPageVC) ? "Outfits" : "Items"
        selectedTab = tab
        onSelectedTabChange?(tab)
        itemsScrollView = nil
        outfitsScrollView = nil
        didScheduleScrollDiscovery = false
        discoverChildScrollViewsIfNeeded()
    }
}
