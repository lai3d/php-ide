import PHPIDECore
import SwiftUI

/// Laravel artisan / Symfony console commands: search, add arguments, run in Output.
struct ConsoleCommandsSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: ConsoleCommand.ID?
    @State private var arguments = ""

    private var filtered: [ConsoleCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return workspace.consoleCommands }
        return workspace.consoleCommands.filter { FuzzyMatch.matches(q, $0.name) || $0.description.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search commands (e.g. make:con, migrate)", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
                .onSubmit { selection = selection ?? filtered.first?.id }
            Divider()
            Group {
                if workspace.isLoadingFramework {
                    ProgressView("Loading commands…").frame(maxHeight: .infinity)
                } else if let error = workspace.frameworkError {
                    ScrollView { Text(error).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                } else {
                    List(filtered, selection: $selection) { command in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(command.name).font(.system(.body, design: .monospaced))
                            if !command.description.isEmpty {
                                Text(command.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tag(command.id)
                        .onTapGesture(count: 2) { selection = command.id; run() }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 8) {
                Text(selection.map { "php \(workspace.framework?.console ?? "") \($0)" } ?? "Select a command")
                    .font(.system(.body, design: .monospaced)).lineLimit(1)
                TextField("arguments and options", text: $arguments)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(run)
                Button("Run", action: run).keyboardShortcut(.defaultAction).disabled(selection == nil || workspace.isRunning)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
        }
        .frame(width: 720, height: 480)
    }

    private func run() {
        guard let selection else { return }
        workspace.runConsoleCommand(selection, arguments: arguments)
        dismiss()
    }
}

/// The application's routes; double-click opens the controller method.
struct RoutesSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: FrameworkRoute.ID?

    private var filtered: [FrameworkRoute] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return workspace.routes }
        return workspace.routes.filter {
            $0.path.localizedCaseInsensitiveContains(q) || ($0.name ?? "").localizedCaseInsensitiveContains(q)
                || ($0.action ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter by path, name or controller", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            Group {
                if workspace.isLoadingFramework {
                    ProgressView("Loading routes…").frame(maxHeight: .infinity)
                } else if let error = workspace.frameworkError {
                    ScrollView { Text(error).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                } else {
                    Table(filtered, selection: $selection) {
                        TableColumn("Method") { Text($0.methods).font(.system(.body, design: .monospaced)) }.width(min: 60, ideal: 90)
                        TableColumn("Path") { Text($0.path).font(.system(.body, design: .monospaced)) }
                        TableColumn("Name") { Text($0.name ?? "").foregroundStyle(.secondary) }
                        TableColumn("Action") { Text($0.action ?? "").lineLimit(1).truncationMode(.head) }
                    }
                    .contextMenu(forSelectionType: FrameworkRoute.ID.self) { _ in
                    } primaryAction: { ids in
                        if let route = workspace.routes.first(where: { ids.contains($0.id) }) { workspace.openController(for: route) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack {
                Text("\(filtered.count) route\(filtered.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                Spacer()
                Button("Open Controller") {
                    if let route = workspace.routes.first(where: { $0.id == selection }) { workspace.openController(for: route) }
                }
                .disabled(selection == nil)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
        }
        .frame(width: 860, height: 480)
    }
}
