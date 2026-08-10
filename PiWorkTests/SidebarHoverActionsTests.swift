import XCTest
import SwiftUI
@testable import PiWork

final class SidebarHoverActionsTests: XCTestCase {
    func testSettingsWindowUsesTheMainWindowChromeStyle() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/App/PiWorkApp.swift"),
            encoding: .utf8
        )
        let settingsScene = try XCTUnwrap(
            source.components(separatedBy: "Settings {").last?
                .components(separatedBy: "/// Gates the app").first
        )

        XCTAssertTrue(settingsScene.contains(".windowStyle(.hiddenTitleBar)"))
        XCTAssertTrue(
            settingsScene.contains(".windowToolbarStyle(.unified(showsTitle: false))")
        )
    }

    func testSettingsGradientExtendsThroughTheTransparentTitlebar() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Auth/Views/ModelProviderSettingsView.swift"
            ),
            encoding: .utf8
        )
        let chromeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Core/UI/TrafficLightPositioner.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(settingsSource.contains(".background(SettingsWindowChrome())"))
        XCTAssertTrue(settingsSource.contains(".ignoresSafeArea(.container, edges: .top)"))
        XCTAssertTrue(chromeSource.contains("window.styleMask.insert(.fullSizeContentView)"))
        XCTAssertTrue(chromeSource.contains("window.titlebarAppearsTransparent = true"))
        XCTAssertTrue(chromeSource.contains("window.titleVisibility = .hidden"))
        XCTAssertTrue(chromeSource.contains("window.toolbar?.showsBaselineSeparator = false"))
    }

    func testSettingsTrafficLightsAreInsetFromTheRoundedSidebarCorner() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Auth/Views/ModelProviderSettingsView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains(
                ".background(TrafficLightPositioner(offset: CGSize(width: 10, height: 6)))"
            )
        )
    }

    func testSettingsChromeReappliesTransparencyAfterWindowLifecycleChanges() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Core/UI/TrafficLightPositioner.swift"
            ),
            encoding: .utf8
        )
        let implementation = try XCTUnwrap(
            source.components(separatedBy: "private final class SettingsWindowChromeView").last?
                .components(separatedBy: "private final class WindowTitlebarDragView").first
        )

        XCTAssertTrue(implementation.contains("NSWindow.didBecomeKeyNotification"))
        XCTAssertTrue(implementation.contains("NSWindow.didResizeNotification"))
        XCTAssertTrue(implementation.contains("NSWindow.didEndLiveResizeNotification"))
        XCTAssertTrue(implementation.contains("NSWindow.didUpdateNotification"))
        XCTAssertTrue(implementation.contains("window.toolbar?.isVisible = false"))
        XCTAssertTrue(implementation.contains("stopObserving()"))
    }

    func testMainWindowTitlebarSupportsDragAndDoubleClickZoom() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/App/Root/ContentView.swift"),
            encoding: .utf8
        )
        let chromeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Core/UI/TrafficLightPositioner.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contentSource.contains("WindowTitlebarDragRegion()"))
        XCTAssertTrue(chromeSource.contains("event.clickCount == 2"))
        XCTAssertTrue(chromeSource.contains("window?.zoom(nil)"))
        XCTAssertTrue(chromeSource.contains("window?.performDrag(with: event)"))
    }

    func testSettingsPresentationDismissesPopoverBeforeDeferringWindowOpen() {
        var events: [String] = []
        var deferredOpen: (() -> Void)?

        SettingsPresentationSequencer.present(
            dismiss: { events.append("dismiss") },
            schedule: { deferredOpen = $0 },
            open: { events.append("open") }
        )

        XCTAssertEqual(events, ["dismiss"])

        deferredOpen?()

        XCTAssertEqual(events, ["dismiss", "open"])
    }

    func testProjectDisclosureStartsCollapsed() {
        let projectID = UUID()
        let state = ProjectDisclosureState()

        XCTAssertFalse(state.isExpanded(projectID))
    }

    func testProjectDisclosureTogglesProjectsIndependently() {
        let firstProjectID = UUID()
        let secondProjectID = UUID()
        var state = ProjectDisclosureState()

        state.toggle(firstProjectID)

        XCTAssertTrue(state.isExpanded(firstProjectID))
        XCTAssertFalse(state.isExpanded(secondProjectID))

        state.toggle(firstProjectID)

        XCTAssertFalse(state.isExpanded(firstProjectID))
    }

    func testSecondaryActionIsHiddenWithoutHover() {
        XCTAssertFalse(SidebarHoverActionVisibility(isHovering: false).showsAction)
    }

    func testSecondaryActionAppearsWhileHovering() {
        XCTAssertTrue(SidebarHoverActionVisibility(isHovering: true).showsAction)
    }

    func testRoundedInteractionDistinguishesHoverAndPress() {
        let hovered = RoundedInteractionVisualState(isHovering: true, isPressed: false)
        let pressed = RoundedInteractionVisualState(isHovering: true, isPressed: true)

        XCTAssertEqual(hovered.overlayOpacity, 0.055, accuracy: 0.001)
        XCTAssertEqual(hovered.scale, 1)
        XCTAssertEqual(pressed.overlayOpacity, 0.10, accuracy: 0.001)
        XCTAssertLessThan(pressed.scale, hovered.scale)
    }

    func testSelectedAndHoveredRowsUseSemanticGrayFills() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Core/UI/AppPalette.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("static let selectedRowFill = Color.primary.opacity(0.075)"))
        XCTAssertTrue(source.contains("static let hoverRowFill = Color.primary.opacity(0.055)"))
    }

    func testPinnedHeaderAndFooterStayOutsideScrollableListWithoutRestyling() throws {
        let source = try sidebarSource()
        let sidebarBody = try XCTUnwrap(
            source.components(separatedBy: "    var body: some View {").dropFirst().first?
                .components(separatedBy: "\n    private func navigationRow").first
        )
        let headerOffset = try XCTUnwrap(sidebarBody.range(of: "SidebarTabHeader(")).lowerBound
        let listOffset = try XCTUnwrap(sidebarBody.range(of: "List(selection:")).lowerBound
        let footerOffset = try XCTUnwrap(sidebarBody.range(of: "UserFooterView()")).lowerBound

        XCTAssertTrue(sidebarBody.contains("VStack(spacing: 0) {"))
        XCTAssertLessThan(headerOffset, listOffset)
        XCTAssertLessThan(listOffset, footerOffset)
        XCTAssertFalse(sidebarBody.contains(".safeAreaInset(edge: .top"))
        XCTAssertFalse(sidebarBody.contains(".safeAreaInset(edge: .bottom"))
        XCTAssertFalse(sidebarBody.contains(".background(.regularMaterial)"))
    }

    func testWorkProjectHeaderStaysOutsideScrollableProjectList() throws {
        let source = try sidebarSource()
        let sidebarBody = try XCTUnwrap(
            source.components(separatedBy: "    var body: some View {").dropFirst().first?
                .components(separatedBy: "\n    private func navigationRow").first
        )
        let workBranch = try XCTUnwrap(
            sidebarBody.components(separatedBy: "            case .work:").last?
                .components(separatedBy: "\n            UserFooterView()").first
        )
        let navigationOffset = try XCTUnwrap(
            workBranch.range(of: "navigationRow(.schedule)")
        ).lowerBound
        let projectHeaderOffset = try XCTUnwrap(
            workBranch.range(of: "LinkedFoldersHeader(onAddFolder: onAddFolder)")
        ).lowerBound
        let projectListOffset = try XCTUnwrap(
            workBranch.range(of: "List {")
        ).lowerBound

        XCTAssertLessThan(navigationOffset, projectHeaderOffset)
        XCTAssertLessThan(projectHeaderOffset, projectListOffset)
        XCTAssertFalse(workBranch.contains("} header: {\n                            LinkedFoldersHeader"))
    }

    func testWorkProjectListDoesNotSelectProjectsWhenFoldersAreToggled() throws {
        let source = try sidebarSource()
        let workBranch = try XCTUnwrap(
            source.components(separatedBy: "            case .work:").last?
                .components(separatedBy: "\n            UserFooterView()").first
        )

        XCTAssertTrue(workBranch.contains("List {"))
        XCTAssertFalse(workBranch.contains("List(selection: $selectedProject)"))
    }

    func testSidebarTabsKeepRaisedWhiteSelectionIndependentFromGrayRows() throws {
        let source = try sidebarSource()

        XCTAssertTrue(source.contains(".fill(isSelected ? AppPalette.raisedSurface : Color.clear)"))
        XCTAssertTrue(source.contains("RoundedInteractionButtonStyle(cornerRadius: 17)"))
        XCTAssertFalse(
            source.contains(
                "RoundedInteractionButtonStyle(cornerRadius: 17, isSelected: isSelected)"
            )
        )
    }

    func testNewActionUsesCompactLabel() throws {
        let source = try sidebarSource()

        XCTAssertTrue(source.contains("title: L10n.string(\"sidebar.new\")"))
        XCTAssertFalse(source.contains("New Session"))
    }

    func testNewActionUsesTransientNavigationInteraction() throws {
        let source = try sidebarSource()
        let newAction = try XCTUnwrap(
            source.components(separatedBy: "title: L10n.string(\"sidebar.new\"),").last?
                .components(separatedBy: ") {").first
        )

        XCTAssertTrue(newAction.contains("isSelected: false"))
        XCTAssertFalse(source.contains("private struct NewSessionRow"))
    }

    func testNewActionAppearsOnlyInChatSidebar() throws {
        let source = try sidebarSource()
        let tabBranches = try XCTUnwrap(
            source.components(separatedBy: "case .chat:").last?
                .components(separatedBy: "case .work:")
        )

        XCTAssertEqual(tabBranches.count, 2)
        XCTAssertTrue(tabBranches[0].contains("L10n.string(\"sidebar.new\")"))
        XCTAssertFalse(tabBranches[1].contains("L10n.string(\"sidebar.new\")"))
    }

    func testWorkNavigationOmitsCustomSectionHeader() throws {
        let source = try sidebarSource()
        let workBranch = try XCTUnwrap(
            source.components(separatedBy: "case .work:").last
        )

        XCTAssertTrue(workBranch.contains("navigationRow(.schedule)"))
        XCTAssertTrue(workBranch.contains("navigationRow(.skills)"))
        XCTAssertTrue(workBranch.contains("navigationRow(.connectedApps)"))
        XCTAssertFalse(
            workBranch.contains("SectionLabel(L10n.string(\"sidebar.custom\"))")
        )
    }

    func testConnectedAppsDestinationUsesExtensionLabel() throws {
        let source = try sidebarSource()

        XCTAssertTrue(
            source.contains(
                "case .connectedApps: return L10n.string(\"sidebar.extensions\")"
            )
        )
        XCTAssertFalse(source.contains("\"关联的应用\""))
    }

    func testLinkedFoldersSectionUsesProjectFolderLabel() throws {
        let source = try sidebarSource()

        XCTAssertTrue(
            source.contains("Text(L10n.string(\"sidebar.project_folders\"))")
        )
        XCTAssertFalse(source.contains("Text(\"已关联的文件夹\")"))
    }

    func testWorkSidebarOmitsTaskRow() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Sidebar/Views/SidebarView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("NavRow(icon: \"square.and.pencil\", title: \"任务\")"))
    }

    func testWorkSidebarRendersSessionsUnderEachProject() throws {
        let source = try sidebarSource()

        XCTAssertTrue(source.contains("workSessionsByProjectPath[project.path]"))
        XCTAssertTrue(source.contains("WorkSessionRow("))
    }

    func testSidebarActivityIsVisibleWhileSessionExecutionIsInFlight() {
        XCTAssertTrue(SessionRecordRunState.submitting.showsSidebarActivity)
        XCTAssertTrue(SessionRecordRunState.running.showsSidebarActivity)
        XCTAssertTrue(SessionRecordRunState.stopping.showsSidebarActivity)
    }

    func testSidebarActivityIsHiddenOutsideExecution() {
        XCTAssertFalse(SessionRecordRunState.opening.showsSidebarActivity)
        XCTAssertFalse(SessionRecordRunState.idle.showsSidebarActivity)
        XCTAssertFalse(SessionRecordRunState.failed.showsSidebarActivity)
    }

    func testWorkSessionRowUsesNativeActivityIndicatorForActiveSession() throws {
        let source = try sidebarSource()
        let sessionRow = try XCTUnwrap(
            source.components(separatedBy: "private struct WorkSessionRow").last?
                .components(separatedBy: "private struct WorkSessionEmptyState").first
        )

        XCTAssertTrue(source.contains("activeSessionIDs.contains(session.id)"))
        XCTAssertTrue(sessionRow.contains("let showsActivity: Bool"))
        XCTAssertTrue(sessionRow.contains("if showsActivity"))
        XCTAssertTrue(sessionRow.contains("ProgressView()"))
        XCTAssertTrue(sessionRow.contains(".controlSize(.small)"))
    }

    func testWorkProjectsRevealSessionsOrEmptyStateOnlyWhenExpanded() throws {
        let source = try sidebarSource()

        XCTAssertTrue(source.contains("projectDisclosureState.isExpanded(project.id)"))
        XCTAssertTrue(source.contains("if isExpanded"))
        XCTAssertTrue(source.contains("WorkSessionEmptyState()"))
        XCTAssertTrue(source.contains("Text(L10n.string(\"sidebar.no_session\"))"))
    }

    func testWorkSessionContextMenuOffersCopyAndDelete() throws {
        let source = try sidebarSource()
        let sessionRow = try XCTUnwrap(
            source.components(separatedBy: "private struct WorkSessionRow").last?
                .components(separatedBy: "private struct WorkSessionEmptyState").first
        )

        XCTAssertTrue(sessionRow.contains(".sessionContextMenu("))
        XCTAssertTrue(sessionRow.contains("sessionID: session.id"))
        XCTAssertTrue(sessionRow.contains("onDelete: onDelete"))
        XCTAssertTrue(source.contains("L10n.string(\"sidebar.copy_session_id\")"))
        XCTAssertTrue(source.contains("L10n.string(\"sidebar.delete_session\")"))
        XCTAssertTrue(source.contains("NSPasteboard.general"))
        XCTAssertTrue(source.contains("onDeleteWorkSession(project, session)"))
    }

    func testChatSessionContextMenuOffersCopyAndDelete() throws {
        let source = try sidebarSource()
        let sessionRow = try XCTUnwrap(
            source.components(separatedBy: "private struct ChatSessionRow").last?
                .components(separatedBy: "private struct FolderRow").first
        )

        XCTAssertTrue(sessionRow.contains("let onDelete: () -> Void"))
        XCTAssertTrue(sessionRow.contains(".sessionContextMenu("))
        XCTAssertTrue(sessionRow.contains("sessionID: session.id"))
        XCTAssertTrue(sessionRow.contains("onDelete: onDelete"))
        XCTAssertTrue(source.contains("onDeleteChatSession(session)"))
    }

    func testSessionContextMenuDoesNotDrawTheDefaultFocusRing() throws {
        let source = try sidebarSource()

        XCTAssertTrue(source.contains("if #available(macOS 14.0, *)"))
        XCTAssertTrue(source.contains("content.focusEffectDisabled()"))
        XCTAssertTrue(source.contains("content.focusable(false)"))
    }

    func testContentViewDeletesChatSessionsUsingTheChatProfile() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/App/Root/ContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("onDeleteChatSession: deleteChatSession"))
        let deletion = try XCTUnwrap(
            source.components(separatedBy: "private func deleteChatSession(").last?
                .components(separatedBy: "private func deleteWorkSession(").first
        )
        XCTAssertTrue(deletion.contains("sessionStore.deleteSession("))
        XCTAssertTrue(deletion.contains("profile: .chat"))
    }

    func testWorkRowsUseShallowHierarchicalInsets() throws {
        let source = try sidebarSource()
        let folderRow = try XCTUnwrap(
            source.components(separatedBy: "private struct FolderRow").last?
                .components(separatedBy: "private struct WorkSessionRow").first
        )
        let sessionRow = try XCTUnwrap(
            source.components(separatedBy: "private struct WorkSessionRow").last?
                .components(separatedBy: "private struct WorkSessionEmptyState").first
        )

        XCTAssertTrue(folderRow.contains(".padding(.leading, 0)"))
        XCTAssertTrue(sessionRow.contains(".padding(.leading, 12)"))
        XCTAssertTrue(sessionRow.contains(".padding(.leading, 20)"))
        XCTAssertFalse(sessionRow.contains(".padding(.leading, 46)"))
    }

    func testProjectRowOnlyTogglesDisclosureUntilNewSessionIsRequested() throws {
        let source = try sidebarSource()
        let folderRow = try XCTUnwrap(
            source.components(separatedBy: "private struct FolderRow").last?
                .components(separatedBy: "private struct WorkSessionRow").first
        )

        XCTAssertTrue(folderRow.contains("Image(systemName: \"folder\")"))
        XCTAssertTrue(folderRow.contains("onToggle()"))
        XCTAssertFalse(folderRow.contains("onSelect()"))
        XCTAssertFalse(source.contains("onSelectWorkProject"))
        XCTAssertTrue(folderRow.contains(".frame(maxWidth: .infinity"))
        XCTAssertFalse(folderRow.contains("chevron.right"))
    }

    func testProjectRowOffersConfirmedRemovalWithoutDeletingTheFolder() throws {
        let source = try sidebarSource()
        let folderRow = try XCTUnwrap(
            source.components(separatedBy: "private struct FolderRow").last?
                .components(separatedBy: "private struct WorkSessionRow").first
        )

        XCTAssertTrue(folderRow.contains(".contextMenu"))
        XCTAssertTrue(folderRow.contains(".confirmationDialog"))
        XCTAssertTrue(folderRow.contains("L10n.string(\"sidebar.remove_project\")"))
        XCTAssertTrue(folderRow.contains("onDelete()"))
        XCTAssertFalse(folderRow.contains("FileManager.default.removeItem"))
    }

    func testContentViewDeletesProjectSessionsBeforeUnlinkingProject() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/App/Root/ContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("onDeleteWorkProject: deleteWorkProject"))
        let deleteSessions = try XCTUnwrap(
            source.range(of: "try await sessionStore.deleteWorkSessions(")
        )
        let unlinkProject = try XCTUnwrap(
            source.range(of: "projectStore.removeProject(project)")
        )
        XCTAssertLessThan(deleteSessions.lowerBound, unlinkProject.lowerBound)
    }

    @MainActor
    func testRemovingProjectKeepsItsFolderOnDisk() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectStoreTests-\(UUID().uuidString)", isDirectory: true)
        let projectFolder = temporaryRoot.appendingPathComponent("kept-project", isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectFolder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let store = ProjectStore(storeURL: temporaryRoot.appendingPathComponent("projects.json"))
        store.addProject(path: projectFolder.path)
        let project = try XCTUnwrap(store.projects.first)

        store.removeProject(project)

        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectFolder.path))
    }

    func testSidebarToggleStaysInTopControlBand() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/App/Root/ContentView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".padding(.top, 44)"))
        XCTAssertTrue(source.contains(".padding(.top, 0)"))
        XCTAssertFalse(source.contains(".padding(.top, 14)"))
    }

    func testSidebarToggleUsesFourPointHorizontalInset() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/App/Root/ContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains(".padding(.horizontal, 4)\n                    .padding(.top, 0)")
        )
        XCTAssertFalse(
            source.contains(".padding(.horizontal, 8)\n                    .padding(.top, 0)")
        )
    }

    func testApplicationChromeOmitsBetaBadges() throws {
        let sidebar = try sidebarSource()
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/App/Root/ContentView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(sidebar.contains("badge: \"BETA\""))
        XCTAssertFalse(content.contains("BetaBadge()"))
    }

    @MainActor
    func testSidebarTabsStayNearTheWindowToolbar() throws {
        let view = SidebarView(
            projectStore: ProjectStore(),
            selectedProject: .constant(nil),
            selectedTab: .constant(.work),
            onAddFolder: {},
            onNewSession: {},
            onNewProjectSession: { _ in }
        )
        .frame(width: 254, height: 600)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        let bitmap = try TestViewRenderer.render(view, size: CGSize(width: 254, height: 600))
        let topBandHeight = 50
        var darkPixelCount = 0

        for y in 0..<topBandHeight {
            for x in 24..<(bitmap.pixelsWide - 24) {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                    color.alphaComponent > 0.5
                else { continue }
                if color.redComponent < 0.45,
                   color.greenComponent < 0.45,
                   color.blueComponent < 0.45 {
                    darkPixelCount += 1
                }
            }
        }

        XCTAssertGreaterThan(
            darkPixelCount,
            0,
            "The Chat and Work tabs should appear in the first 50 points of the sidebar"
        )
    }

    func testStartingProjectSessionSelectsRequestedProject() {
        let project = PiProject(name: "pi-work", path: "/tmp/pi-work")
        var state = WorkSessionSelection()

        state.startNewSession(for: project)

        XCTAssertEqual(state.selectedProject, project)
    }

    func testSelectingSessionTransfersHighlightFromProjectRow() {
        let project = PiProject(name: "pi-work", path: "/tmp/pi-work")
        var state = WorkSessionSelection()

        state.selectProject(project)
        XCTAssertEqual(state.sidebarItem, .project(project.id))

        state.selectSession("session-1", in: project)

        XCTAssertEqual(state.selectedProject, project)
        XCTAssertEqual(
            state.sidebarItem,
            .session(projectID: project.id, sessionID: "session-1")
        )
    }

    func testStartingProjectSessionRenewsSessionIdentity() {
        let oldID = UUID()
        let newID = UUID()
        let project = PiProject(name: "pi-work", path: "/tmp/pi-work")
        var state = WorkSessionSelection(sessionID: oldID)

        state.startNewSession(for: project, sessionID: newID)

        XCTAssertEqual(state.sessionID, newID)
        XCTAssertNotEqual(state.sessionID, oldID)
    }

    private func sidebarSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Sidebar/Views/SidebarView.swift"),
            encoding: .utf8
        )
    }
}
