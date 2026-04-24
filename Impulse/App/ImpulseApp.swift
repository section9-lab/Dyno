//
// ImpulseApp.swift
// Impulse
//
// Created by jackwang on 2026/3/27.
//

import SwiftUI
import SwiftData

@main
struct ImpulseApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @StateObject private var agent = AgentManager.shared
    @StateObject private var ocrManager = OCRManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
                    let appPath = Bundle.main.bundleURL.path
                    let executablePath = Bundle.main.executableURL?.path ?? "unknown"
                    let storageDirectory = agent.storageDirectoryURL

                    print("🔧 [APP] Bundle ID: \(bundleId)")
                    print("🔧 [APP] App Path: \(appPath)")
                    print("🔧 [APP] Executable Path: \(executablePath)")
                    print("🔧 [APP] Impulse storage directory: \(storageDirectory.path)")

                    ocrManager.start(storageDirectory: storageDirectory)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
