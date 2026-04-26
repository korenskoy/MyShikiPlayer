//
//  AppShellView.swift
//  MyShikiPlayer
//
//  Sticky top bar + content of the selected tab. NavigationSplitView is
//  removed — its sidebar would conflict with the filters column in Catalog.
//
//  Global browser-style history (NavigationHistoryStore) records tab
//  switches and detail openings; TopBar shows back/forward controls with
//  hover-tooltips and live titles pulled from history.
//

import AppKit
import SwiftUI

struct AppShellView: View {
    @ObservedObject var auth: ShikimoriAuthController
    @StateObject private var navigation = NavigationState()
    @StateObject private var history = NavigationHistoryStore()
    @State private var isSearchPresented: Bool = false
    @State private var searchOpenedDetailId: Int?
    @State private var mouseSideButtonsMonitor: Any?
    @AppStorage("app.theme") private var themeId: String = AppTheme.paper.id

    private var theme: AppTheme { AppTheme.byId(themeId) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                AppTopBar(
                    navigation: navigation,
                    auth: auth,
                    history: history,
                    isDetailVisible: searchOpenedDetailId != nil,
                    onGoBack: { applyHistoryStep(history.goBack()) },
                    onGoForward: { applyHistoryStep(history.goForward()) },
                    onOpenSearch: { isSearchPresented = true }
                )
                // Per the reference (screens-detail.jsx) — TopBar stays visible
                // and the detail screen goes BELOW the header. No overlay.
                Group {
                    if let id = searchOpenedDetailId, let config = auth.configuration {
                        AnimeDetailsView(
                            auth: auth,
                            configuration: config,
                            shikimoriId: id,
                            onClose: closeDetails,
                            onOpenAnime: { nested in
                                searchOpenedDetailId = nested.id
                            },
                            onOpenAnimeId: { id in
                                searchOpenedDetailId = id
                            },
                            onTitleResolved: { resolvedId, title in
                                history.updateDetailTitle(shikimoriId: resolvedId, title: title)
                            }
                        )
                        // id-trigger: when id changes (opening a "Related" item)
                        // we recreate the View — otherwise the @StateObject VM
                        // gets stuck on the previous shikimoriId.
                        .id(id)
                    } else {
                        branchView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // ⌘K shortcut bound to an invisible button — the SwiftUI shortcut
            // API only works on buttons/menus.
            Button { isSearchPresented = true } label: { EmptyView() }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

            // ⌘[ / ⌘] — Safari-standard back/forward. Invisible buttons,
            // disabled when there is nowhere to go.
            Button { applyHistoryStep(history.goBack()) } label: { EmptyView() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!history.canGoBack)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

            Button { applyHistoryStep(history.goForward()) } label: { EmptyView() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!history.canGoForward)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

            // Esc — close the opened details. There is no dedicated button in
            // the UI; navigation back happens via TopBar (any tab) or Esc.
            if searchOpenedDetailId != nil {
                Button { closeDetails() } label: { EmptyView() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }

            if isSearchPresented {
                SearchModalView(
                    configuration: auth.configuration,
                    onClose: { isSearchPresented = false },
                    onSelect: { item in
                        isSearchPresented = false
                        searchOpenedDetailId = item.id
                    }
                )
                .transition(.opacity)
                .zIndex(50)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isSearchPresented)
        .animation(.easeInOut(duration: 0.22), value: searchOpenedDetailId)
        .onAppear {
            seedHistoryIfNeeded()
            installMouseSideButtonsMonitor()
        }
        .onDisappear { removeMouseSideButtonsMonitor() }
        .onChange(of: navigation.selectedBranch) { _, newBranch in
            // Switching tabs = exit details. During our own navigation
            // (back/forward) we don't push — the isNavigating flag suppresses it.
            if searchOpenedDetailId != nil {
                searchOpenedDetailId = nil
            }
            guard !history.isNavigating else { return }
            history.push(.branch(newBranch))
        }
        .onChange(of: searchOpenedDetailId) { _, newId in
            guard !history.isNavigating else { return }
            guard let id = newId else { return }
            history.push(.detail(shikimoriId: id, title: nil))
        }
        .background(theme.bg)
        .appTheme(theme)
    }

    private func closeDetails() {
        withAnimation(.easeInOut(duration: 0.2)) {
            searchOpenedDetailId = nil
        }
    }

    /// On launch we either seed an empty stack or restore the current tab
    /// from persisted history. We don't reopen Detail — that is heavy state;
    /// the user can return to it via back.
    private func seedHistoryIfNeeded() {
        guard let current = history.currentEntry else {
            history.push(.branch(navigation.selectedBranch))
            return
        }
        switch current {
        case .branch(let branch):
            if navigation.selectedBranch != branch {
                history.performNavigation {
                    navigation.selectedBranch = branch
                }
            }
        case .detail:
            // Previous session ended on detail — push a new entry for the
            // current default tab; old history stays in the back stack.
            history.push(.branch(navigation.selectedBranch))
        }
    }

    private func applyHistoryStep(_ entry: NavigationHistoryStore.Entry?) {
        guard let entry else { return }
        history.performNavigation {
            switch entry {
            case .branch(let branch):
                searchOpenedDetailId = nil
                navigation.selectedBranch = branch
            case .detail(let id, _):
                searchOpenedDetailId = id
            }
        }
    }

    /// Wires the mouse "back"/"forward" side buttons (NSEvent.buttonNumber 3
    /// and 4) to the history controls. Local monitor → only fires while the
    /// app is frontmost, so we never swallow events for other windows.
    private func installMouseSideButtonsMonitor() {
        guard mouseSideButtonsMonitor == nil else { return }
        mouseSideButtonsMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            switch event.buttonNumber {
            case 3:
                applyHistoryStep(history.goBack())
                return nil
            case 4:
                applyHistoryStep(history.goForward())
                return nil
            default:
                return event
            }
        }
    }

    private func removeMouseSideButtonsMonitor() {
        if let monitor = mouseSideButtonsMonitor {
            NSEvent.removeMonitor(monitor)
            mouseSideButtonsMonitor = nil
        }
    }

    @ViewBuilder
    private var branchView: some View {
        switch navigation.selectedBranch {
        case .home:
            HomeView(
                auth: auth,
                onOpenDetails: { id in searchOpenedDetailId = id },
                onOpenSchedule: { navigation.selectedBranch = .schedule }
            )
        case .catalog:
            CatalogView(auth: auth)
        case .schedule:
            ScheduleView(
                auth: auth,
                onOpenDetails: { id in searchOpenedDetailId = id }
            )
        case .social:
            SocialView(
                auth: auth,
                onOpenAnime: { id in searchOpenedDetailId = id }
            )
        case .myLists:
            LibraryView(
                auth: auth,
                onOpenDetails: { id in searchOpenedDetailId = id }
            )
        case .history:
            HistoryView(
                auth: auth,
                onOpenDetails: { id in searchOpenedDetailId = id }
            )
        case .profile:
            ProfileView(
                auth: auth,
                onOpenAnime: { id in searchOpenedDetailId = id },
                onSignOut: { auth.signOut() }
            )
        }
    }
}
