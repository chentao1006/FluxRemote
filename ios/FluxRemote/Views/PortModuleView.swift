import SwiftUI

struct PortModuleView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var selection: NavigationItem?

    @State private var groups: [PortProcessGroup] = []
    @State private var summary: PortSummary = .empty
    @State private var searchText = ""
    @State private var stateFilter = "all"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var refreshTask: Task<Void, Never>?
    @State private var loadingAction: [String: String] = [:]
    @State private var groupToActOn: PortProcessGroup?
    @State private var showingTerminateConfirmation = false
    @State private var showingKillConfirmation = false

    private var stateOptions: [String] {
        Array(Set(groups.flatMap { $0.ports.map(\.state).filter { !$0.isEmpty } })).sorted()
    }

    private var filteredGroups: [PortProcessGroup] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return groups.compactMap { group in
            let ports = group.ports.filter { port in
                let matchesState = stateFilter == "all" || port.state == stateFilter
                let haystack = [
                    group.command,
                    group.pid,
                    group.user,
                    group.fullCommand,
                    port.protocolName,
                    "\(port.port)",
                    port.endpoint,
                    port.state
                ].joined(separator: " ").lowercased()
                return matchesState && (keyword.isEmpty || haystack.contains(keyword))
            }
            return ports.isEmpty ? nil : PortProcessGroup(
                pid: group.pid,
                command: group.command,
                user: group.user,
                cpu: group.cpu,
                mem: group.mem,
                ppid: group.ppid,
                start: group.start,
                fullCommand: group.fullCommand,
                ports: ports
            )
        }
    }

    // 当前筛选状态的本地化显示
    var stateFilterLabel: String {
        stateFilter == "all" ? languageManager.t("ports.allStates") : localizedState(stateFilter)
    }

    // 当前筛选后端口总数
    var filteredPortCount: Int {
        filteredGroups.reduce(0) { $0 + $1.ports.count }
    }

    var body: some View {
        ZStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        statView(value: summary.ports, label: languageManager.t("ports.usedPorts"))
                        statView(value: summary.processes, label: languageManager.t("ports.processGroups"))
                        statView(value: summary.listening, label: languageManager.t("ports.listeningPorts"))
                    }
                    .padding(.vertical, 4)
                }

                if let errorMessage, groups.isEmpty {
                    ContentUnavailableView(languageManager.t("ports.fetchFailed"), systemImage: "network.slash", description: Text(errorMessage))
                } else if filteredGroups.isEmpty && !isLoading {
                    ContentUnavailableView(languageManager.t("ports.noData"), systemImage: "network")
                } else {
                    ForEach(filteredGroups) { group in
                        portGroupRow(group)
                    }
                }
            }
            .listStyle(.insetGrouped)

            if isLoading && groups.isEmpty {
                LoadingView()
            }
        }
        .navigationTitle(languageManager.t("ports.title"))
        .searchable(text: $searchText, prompt: languageManager.t("ports.searchPlaceholder"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker(languageManager.t("ports.state"), selection: $stateFilter) {
                        Text(languageManager.t("ports.allStates")).tag("all")
                        ForEach(stateOptions, id: \.self) { state in
                            Text(localizedState(state)).tag(state)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(stateFilterLabel)
                            .font(.caption2)
                        Text("(\(filteredPortCount))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .refreshable {
            await fetchData()
        }
        .onAppear {
            if groups.isEmpty && !apiClient.portGroups.isEmpty {
                groups = apiClient.portGroups
                summary = apiClient.portSummary
            }
            Task { await fetchData() }
            refreshTask?.cancel()
            refreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    await fetchData(silent: true)
                }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
        }
        .alert(languageManager.t("processes.terminateConfirm"), isPresented: $showingTerminateConfirmation) {
            Button(languageManager.t("processes.terminate"), role: .destructive) {
                if let groupToActOn {
                    Task { await performAction(pid: groupToActOn.pid, action: "term") }
                }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) { }
        } message: {
            Text(groupToActOn.map { "\($0.command) (PID: \($0.pid))" } ?? "")
        }
        .alert(languageManager.t("processes.forceKillConfirm"), isPresented: $showingKillConfirmation) {
            Button(languageManager.t("processes.forceKill"), role: .destructive) {
                if let groupToActOn {
                    Task { await performAction(pid: groupToActOn.pid, action: "kill") }
                }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) { }
        } message: {
            Text(groupToActOn.map { "\($0.command) (PID: \($0.pid))" } ?? "")
        }
    }

    private func statView(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func portGroupRow(_ group: PortProcessGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(group.command)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text("PID \(group.pid)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color("AccentColor"))
                            .clipShape(Capsule())
                    }

                    Text("\(languageManager.t("processes.user")): \(group.user.isEmpty ? languageManager.t("common.unknown") : group.user) · CPU \(group.cpu)% · MEM \(group.mem)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !group.fullCommand.isEmpty {
                        Text(group.fullCommand)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    actionButton(icon: "stop", color: .orange, isLoading: loadingAction[group.pid] == "term") {
                        groupToActOn = group
                        showingTerminateConfirmation = true
                    }
                    .disabled(loadingAction[group.pid] != nil)

                    actionButton(icon: "trash", color: .red, isLoading: loadingAction[group.pid] == "kill") {
                        groupToActOn = group
                        showingKillConfirmation = true
                    }
                    .disabled(loadingAction[group.pid] != nil)
                }
            }

            LazyVGrid(columns: portChipColumns, alignment: .leading, spacing: 8) {
                ForEach(group.ports) { port in
                    portChip(port)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var portChipColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: horizontalSizeClass == .regular ? 320 : 320,
                    maximum: horizontalSizeClass == .regular ? 360 : .infinity
                ),
                spacing: 8,
                alignment: .topLeading
            )
        ]
    }

    private func portChip(_ port: PortEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color(for: port.state))
                    .frame(width: 8, height: 8)
                Text(verbatim: String(port.port))
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color("AccentColor"))
                Text(port.protocolName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if (port.connectionCount ?? 1) > 1 {
                    Text("x\(port.connectionCount ?? 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if !port.state.isEmpty {
                    Text(localizedState(port.state))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color(for: port.state).opacity(0.12))
                        .foregroundStyle(color(for: port.state))
                        .clipShape(Capsule())
                }
            }

            Text(port.endpoint)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actionButton(icon: String, color: Color, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(width: 32, height: 32)
            } else {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 32, height: 32)
                        .background(color.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func color(for state: String) -> Color {
        switch state {
        case "LISTEN": return .green
        case "ESTABLISHED": return .blue
        default: return .orange
        }
    }

    private func localizedState(_ state: String) -> String {
        let key = "ports.state.\(state.lowercased())"
        let localized = languageManager.t(key)
        return localized == key ? state : localized
    }

    @MainActor
    private func fetchData(silent: Bool = false) async {
        guard selection == .ports || selection == .more else { return }
        if !silent { isLoading = groups.isEmpty }
        errorMessage = nil
        do {
            let response: PortsResponse = try await apiClient.request("/api/system/ports")
            groups = response.data
            summary = response.summary
            apiClient.portGroups = response.data
            apiClient.portSummary = response.summary
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    @MainActor
    private func performAction(pid: String, action: String) async {
        loadingAction[pid] = action
        do {
            let _: ActionResponse = try await apiClient.request("/api/system/ports", method: "POST", body: ["action": action, "pid": pid])
            await fetchData()
        } catch {
            errorMessage = error.localizedDescription
        }
        loadingAction[pid] = nil
    }
}

#Preview {
    NavigationStack {
        PortModuleView(selection: .constant(.ports))
            .environment(RemoteAPIClient())
            .environment(AppLanguageManager())
    }
}
