import PHPIDECore
import SwiftUI

/// PHP ▸ Database (.env)…: the project's connection settings, with a hand-off to DBIDE.
struct DatabaseSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var revealPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Database", systemImage: "cylinder.split.1x2").font(.title2.weight(.semibold))
            if let db = workspace.databaseSettings {
                Form {
                    LabeledContent("Driver", value: db.dialect)
                    if db.dialect == "sqlite" {
                        LabeledContent("File") { Text(db.filePath).textSelection(.enabled).lineLimit(2).truncationMode(.head) }
                    } else {
                        LabeledContent("Host", value: db.host + (db.port.map { ":\($0)" } ?? ""))
                        LabeledContent("Database", value: db.database.isEmpty ? "—" : db.database)
                        LabeledContent("User", value: db.user.isEmpty ? "—" : db.user)
                        LabeledContent("Password") {
                            HStack {
                                Text(revealPassword ? db.password : String(repeating: "•", count: min(db.password.count, 12)))
                                    .textSelection(.enabled)
                                if !db.password.isEmpty {
                                    Button(revealPassword ? "Hide" : "Show") { revealPassword.toggle() }.buttonStyle(.link)
                                }
                            }
                        }
                    }
                    LabeledContent("URL") { Text(db.url()).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                    LabeledContent("From", value: db.source)
                }
                .formStyle(.grouped)
                if !workspace.isDBIDEInstalled {
                    Text("DBIDE isn't installed. Get it from IDE Toolbox to browse this database.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Text("No database settings found in .env or .env.local.\nPHPIDE reads Laravel's DB_CONNECTION / DB_HOST / … and Symfony's DATABASE_URL.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Copy URL") { workspace.copyDatabaseURL(includingPassword: false) }
                    .disabled(workspace.databaseSettings == nil)
                Button("Copy URL with Password") { workspace.copyDatabaseURL(includingPassword: true) }
                    .disabled(workspace.databaseSettings?.password.isEmpty ?? true)
                Spacer()
                Button("Open DBIDE") { workspace.openDBIDE(); dismiss() }
                    .disabled(workspace.databaseSettings == nil || !workspace.isDBIDEInstalled)
                    .help("Opens this connection in DBIDE (older DBIDE versions: launches it with the URL on the clipboard)")
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
