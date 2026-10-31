import PHPIDECore
import SwiftUI

/// PHP ▸ Composer ▸ Packages…: direct dependencies, their installed and latest versions; add / update / remove.
struct ComposerPackagesSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ComposerPackage.ID?
    @State private var newPackage = ""
    @State private var newIsDev = false

    private var selected: ComposerPackage? { workspace.packages.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            if workspace.packages.isEmpty {
                ContentUnavailableView("No composer.json dependencies", systemImage: "shippingbox",
                                       description: Text("Add a package below, or run composer init in the Terminal."))
                    .frame(maxHeight: .infinity)
            } else {
                Table(workspace.packages, selection: $selection) {
                    TableColumn("Package") { package in
                        HStack(spacing: 6) {
                            Text(package.name).fontWeight(package.isPlatform ? .regular : .medium)
                            if package.isDev { Text("dev").font(.caption2).padding(.horizontal, 4).background(.quaternary, in: Capsule()) }
                        }
                    }
                    TableColumn("Constraint") { Text($0.constraint).monospaced() }.width(min: 70, ideal: 90)
                    TableColumn("Installed") { Text($0.installed ?? "—").monospaced().foregroundStyle(.secondary) }
                        .width(min: 70, ideal: 90)
                    TableColumn("Latest") { package in
                        if let latest = package.latest, package.latestStatus != "up-to-date" {
                            Text(latest).monospaced()
                                .foregroundStyle(package.latestStatus == "semver-safe-update" ? .green : .orange)
                                .help(package.latestStatus == "semver-safe-update" ? "Update within the constraint" : "Major update: needs a new constraint")
                        } else {
                            Text(workspace.didCheckOutdated && !package.isPlatform ? "✓ up to date" : "").foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 70, ideal: 90)
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("vendor/package or vendor/package:^1.0", text: $newPackage)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                    .onSubmit(add)
                Toggle("Dev", isOn: $newIsDev).toggleStyle(.checkbox)
                Button("Require", action: add)
                    .disabled(!Composer.isValidPackageName(String(newPackage.split(separator: ":").first ?? "")) || workspace.isRunning)
                Spacer()
                Button("Update") { if let selected { workspace.updatePackage(selected) } }
                    .disabled(selected == nil || selected?.isPlatform == true || workspace.isRunning)
                Button("Remove") { if let selected { workspace.removePackage(selected) } }
                    .disabled(selected == nil || selected?.isPlatform == true || workspace.isRunning)
                Button {
                    Task { await workspace.checkOutdatedPackages() }
                } label: {
                    if workspace.isCheckingOutdated { ProgressView().controlSize(.small) } else { Text("Check for Updates") }
                }
                .disabled(workspace.isCheckingOutdated)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(10)
            if workspace.isRunning {
                Text("composer is running — see the Output panel").font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            }
        }
        .frame(width: 760, height: 420)
    }

    private func add() {
        let spec = newPackage.trimmingCharacters(in: .whitespaces)
        guard Composer.isValidPackageName(String(spec.split(separator: ":").first ?? "")) else { return }
        workspace.requirePackage(spec, dev: newIsDev)
        newPackage = ""
    }
}
