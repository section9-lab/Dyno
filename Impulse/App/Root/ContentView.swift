//
// ContentView.swift
// Impulse
//
// Created by jackwang on 2026/3/27.
//
//  Created by jackwang on 2026/3/27.
//

import SwiftAgent
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp) private var items: [Item]
    @StateObject private var vm = ChatViewModel()
    @StateObject private var agent = AgentManager.shared

    private var modelOptions: [ModelOption] {
        let provider = agent.registry.provider(for: agent.config.providerId)
        var options = (provider?.models ?? []).map { model in
            ModelOption(id: model.id, displayName: model.name, isInstalled: model.isLive)
        }

        // Ensure current model is in the list
        if !agent.config.modelId.isEmpty,
           !options.contains(where: { $0.id == agent.config.modelId }) {
            options.insert(ModelOption(id: agent.config.modelId, displayName: agent.config.modelId, isInstalled: true), at: 0)
        }

        return options
    }

    private var sortedConversations: [ConversationThread] {
        vm.sortedConversations(from: items)
    }

    private var selectedConversation: ConversationThread? {
        vm.selectedConversation(from: items)
    }

    private var displayedItems: [Item] {
        vm.displayedItems(from: items)
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if !vm.isSidebarCollapsed {
                    ChatSidebarView(
                        conversations: sortedConversations,
                        selectedID: vm.selectedSidebarMessageID,
                        onNewChat: startNewChat,
                        onSelect: { vm.selectedSidebarMessageID = $0.id },
                        onRename: requestRename,
                        onDelete: deleteConversation,
                        onSettings: openSettings,
                        onHelp: openHelp,
                        onLogout: handleLogout
                    )
                    .frame(width: vm.sidebarWidth)

                    sidebarResizeHandle
                }

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 20) {
                                ForEach(displayedItems) { item in
                                    if item.kind == "compaction_summary" {
                                        EmptyView()
                                            .id(item.id)
                                    } else if item.kind == "tool_execution",
                                              let payload = decodePersistedToolExecution(from: item.content)
                                    {
                                        PersistedToolExecutionMessageView(execution: payload)
                                            .id(item.id)
                                    } else {
                                        MessageView(item: item)
                                            .id(item.id)
                                    }
                                }

                                AgentResponseView(agent: agent)
                                    .id("agent_response")
                            }
                            .padding(.top, 10)
                            .padding(.bottom, 20)
                        }
                        .onChange(of: items.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(displayedItems.last?.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: agent.isResponding) { _, responding in
                            if responding {
                                proxy.scrollTo("agent_response", anchor: .bottom)
                            }
                        }
                        .onChange(of: vm.selectedSidebarMessageID) { _, _ in
                            scrollToBottom(proxy: proxy, id: selectedConversation?.messages.last?.id)
                        }
                    }

                    InputBar(
                        inputText: $vm.inputText,
                        modelName: agent.config.modelId,
                        modelOptions: modelOptions,
                        isResponding: agent.isResponding,
                        onSelectModel: selectModel,
                        onSend: sendMessage
                    )
                }
            }
            .background(Color(red: 0.95, green: 0.95, blue: 0.96))
            .navigationTitle("")
            .toolbarBackground(Color(red: 0.95, green: 0.95, blue: 0.96), for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        toggleSidebar()
                    } label: {
                        Image(systemName: vm.isSidebarCollapsed ? "sidebar.left" : "sidebar.leading")
                    }
                }
            }
            .sheet(isPresented: $vm.showConfigSheet) {
                ModelProviderConfigView(agent: agent)
            }
            .alert("Rename chat", isPresented: $vm.showRenameDialog) {
                TextField("Chat title", text: $vm.renameDraft)
                Button("Cancel", role: .cancel) {
                    vm.renamingItemID = nil
                }
                Button("Save") {
                    applyRename()
                }
                .disabled(!vm.renameDraft.isNotBlank)
            } message: {
                Text("Rename selected chat in sidebar")
            }
            .task {
                loadConversationsFromSessionFilesIfNeeded()
                await agent.refreshServiceStatus()
                vm.selectedSidebarMessageID = vm.selectedSidebarMessageID ?? sortedConversations.first?.id
                persistConversationsToSessionFiles()
            }
            .onChange(of: items.count) { _, _ in
                if !vm.isImportingSessionFiles {
                    persistConversationsToSessionFiles()
                }
            }
        }
    }

    private var sidebarResizeHandle: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(Color.black.opacity(0.16))
                .frame(width: 1)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if vm.dragSidebarStartWidth == nil {
                        vm.dragSidebarStartWidth = vm.sidebarWidth
                    }
                    guard let start = vm.dragSidebarStartWidth else { return }
                    vm.sidebarWidth = min(max(start + value.translation.width, 240), 520)
                }
                .onEnded { _ in
                    vm.lastExpandedSidebarWidth = vm.sidebarWidth
                    vm.dragSidebarStartWidth = nil
                }
        )
    }

    private func toggleSidebar() {
        vm.toggleSidebar()
    }

    private func startNewChat() {
        vm.startNewChat(agent: agent)
    }

    private func loadConversationsFromSessionFilesIfNeeded() {
        vm.loadConversationsFromSessionFilesIfNeeded(items: items, modelContext: modelContext, agent: agent)
    }

    private func persistConversationsToSessionFiles() {
        vm.persistConversationsToSessionFiles(items: items, agent: agent)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, id: AnyHashable?) {
        guard let id = id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    private func decodePersistedToolExecution(from raw: String) -> PersistedToolExecution? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PersistedToolExecution.self, from: data)
    }

    private func sendMessage() {
        vm.sendMessage(modelContext: modelContext, agent: agent, conversationItems: displayedItems) {
            persistConversationsToSessionFiles()
        }
    }

    private func selectModel(_ modelId: String) {
        guard modelId != agent.config.modelId else { return }

        var next = agent.config
        next.modelId = modelId

        Task {
            await agent.applyConfig(next)
        }
    }

    private func requestRename(_ conversation: ConversationThread) {
        vm.requestRename(conversation)
    }

    private func applyRename() {
        let didRename = vm.applyRename(items: items)
        guard didRename else { return }
        persistConversationsToSessionFiles()
    }

    private func deleteConversation(_ conversation: ConversationThread) {
        vm.deleteConversation(conversation, items: items, modelContext: modelContext)
        persistConversationsToSessionFiles()
    }

    private func openSettings() {
        vm.showConfigSheet = true
    }

    private func openHelp() {
        if let url = URL(string: "https://github.com/section9-lab/Impulse/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleLogout() {
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
