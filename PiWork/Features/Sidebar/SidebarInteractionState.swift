import Foundation

struct ProjectDisclosureState: Equatable {
    private(set) var expandedProjectIDs: Set<UUID> = []

    func isExpanded(_ projectID: UUID) -> Bool {
        expandedProjectIDs.contains(projectID)
    }

    mutating func toggle(_ projectID: UUID) {
        if expandedProjectIDs.contains(projectID) {
            expandedProjectIDs.remove(projectID)
        } else {
            expandedProjectIDs.insert(projectID)
        }
    }
}

struct SidebarHoverActionVisibility {
    let isHovering: Bool

    var showsAction: Bool { isHovering }
}

enum WorkSidebarItem: Equatable {
    case project(UUID)
    case session(projectID: UUID, sessionID: String)
}

struct WorkSessionSelection: Equatable {
    var selectedProject: PiProject?
    private(set) var sessionID: UUID
    private(set) var sidebarItem: WorkSidebarItem?

    init(
        selectedProject: PiProject? = nil,
        sessionID: UUID = UUID(),
        sidebarItem: WorkSidebarItem? = nil
    ) {
        self.selectedProject = selectedProject
        self.sessionID = sessionID
        self.sidebarItem = sidebarItem
    }

    mutating func startNewSession(
        for project: PiProject? = nil,
        sessionID: UUID = UUID()
    ) {
        selectedProject = project
        self.sessionID = sessionID
        sidebarItem = project.map { .project($0.id) }
    }

    mutating func selectProject(_ project: PiProject) {
        selectedProject = project
        sidebarItem = .project(project.id)
    }

    mutating func selectSession(_ sessionID: String, in project: PiProject) {
        selectedProject = project
        sidebarItem = .session(projectID: project.id, sessionID: sessionID)
    }
}
