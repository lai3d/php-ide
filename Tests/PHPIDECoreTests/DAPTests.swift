import Foundation
import Testing
@testable import PHPIDECore

/// End-to-end: node + vscode-php-debug + php with Xdebug (loaded per run).
/// Runs only when the adapter is installed (or PHPIDE_PHP_DEBUG_JS points at phpDebug.js).
@Suite(.serialized) struct DAPTests {
    nonisolated static let adapter = ProcessInfo.processInfo.environment["PHPIDE_PHP_DEBUG_JS"].map(URL.init(fileURLWithPath:))
        ?? PHPDebugAdapter.installedScript()
    nonisolated static let ready = adapter != nil && ToolLocator.find("node") != nil && ToolLocator.find("php") != nil

    struct Session {
        let client: DAPClient
        let events: AsyncStream<(String, JSONValue)>
        let dir: URL
    }

    private func launch(_ source: String, breakpoints: [[String: JSONValue]]) async throws -> Session {
        let php = try #require(ToolLocator.find("php"))
        let xdebug = await Xdebug.status(php: php)
        try #require(xdebug.isAvailable, "Xdebug isn't installed (pecl install xdebug)")
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-dap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let dir = base.canonicalFileURL
        let script = dir.appendingPathComponent("main.php")
        try source.write(to: script, atomically: true, encoding: .utf8)

        let client = DAPClient()
        let (events, continuation) = AsyncStream<(String, JSONValue)>.makeStream()
        client.onEvent = { continuation.yield(($0, $1)) }
        try client.start(executable: try #require(ToolLocator.find("node")), arguments: [try #require(Self.adapter).path],
                         directory: dir, environment: ToolLocator.environment())
        _ = try await client.request("initialize", arguments: [
            "clientID": "phpide", "adapterID": "php", "linesStartAt1": true, "columnsStartAt1": true, "pathFormat": "path",
        ])
        _ = try await client.request("launch", arguments: PHPDebugAdapter.launchArguments(
            program: script.path, cwd: dir.path, php: php.path, xdebug: xdebug))
        await client.waitForEvent("initialized")
        let set = try await client.request("setBreakpoints", arguments: [
            "source": ["path": .string(script.path)], "breakpoints": .array(breakpoints.map(JSONValue.object)),
        ])
        #expect(set["breakpoints"]?.arrayValue?.count == breakpoints.count)
        _ = try await client.request("configurationDone")
        return Session(client: client, events: events, dir: dir)
    }

    /// The thread of the next `stopped` event, or nil if the program ended (or the adapter went away) first.
    private func firstStop(_ events: AsyncStream<(String, JSONValue)>) async -> Int? {
        for await (event, body) in events {
            if event == "stopped" { return body["threadId"]?.intValue ?? 1 }
            if event == "terminated" || event == "exited" { return nil }
            if event == "output", let text = body["output"]?.stringValue { print("adapter:", text, terminator: "") }
        }
        return nil
    }

    @Test(.enabled(if: ready), .timeLimit(.minutes(1)))
    func launchesBreaksInspectsStepsAndContinues() async throws {
        let session = try await launch("""
            <?php
            $point = ['x' => 3, 'y' => 4];
            $total = $point['x'] + $point['y'];
            echo "total $total\\n";

            """, breakpoints: [["line": 3]])
        let client = session.client
        defer { try? FileManager.default.removeItem(at: session.dir) }

        var thread: Int?
        thread = await firstStop(session.events)
        let threadID = try #require(thread)
        let frames = StackFrame.parseAll(try await client.request("stackTrace", arguments: ["threadId": .int(threadID)]))
        #expect(frames.first?.line == 3)
        #expect(frames.first?.path?.hasSuffix("/main.php") == true)

        let scopes = DebugVariable.parseScopes(try await client.request("scopes", arguments: ["frameId": .int(frames[0].id)]))
        let locals = try #require(scopes.first { $0.name == "Locals" })
        let variables = DebugVariable.parseVariables(try await client.request("variables", arguments: [
            "variablesReference": .int(locals.variablesReference),
        ]))
        let point = try #require(variables.first { $0.name == "$point" })
        #expect(point.variablesReference > 0)
        let entries = DebugVariable.parseVariables(try await client.request("variables", arguments: [
            "variablesReference": .int(point.variablesReference),
        ]))
        #expect(entries.map(\.name) == ["x", "y"] && entries.map(\.value) == ["3", "4"])

        let evaluated = try await client.request("evaluate", arguments: [
            "expression": "$point['x'] * 10", "frameId": .int(frames[0].id),
            "context": .string(PHPDebugAdapter.evaluateContext(forWatch: "$point['x'] * 10")),
        ])
        #expect(evaluated["result"]?.stringValue == "30")
        let watched = try await client.request("evaluate", arguments: [
            "expression": "$point['y']", "frameId": .int(frames[0].id),
            "context": .string(PHPDebugAdapter.evaluateContext(forWatch: "$point['y']")),
        ])
        #expect(watched["result"]?.stringValue == "4")

        _ = try await client.request("next", arguments: ["threadId": .int(threadID)])
        _ = try #require(await firstStop(session.events), "ran to the end instead of stopping after the step")
        let afterStep = StackFrame.parseAll(try await client.request("stackTrace", arguments: ["threadId": .int(threadID)]))
        #expect(afterStep.first?.line == 4)

        var sawOutput = false
        _ = try await client.request("continue", arguments: ["threadId": .int(threadID)])
        for await (event, body) in session.events {
            if event == "output", body["output"]?.stringValue?.contains("total 7") == true { sawOutput = true }
            if event == "terminated" { break }
        }
        #expect(sawOutput)
        await client.shutdown()
    }

    @Test(.enabled(if: ready), .timeLimit(.minutes(1)))
    func conditionalBreakpoint() async throws {
        let session = try await launch("""
            <?php
            for ($i = 0; $i < 5; $i++) {
                $square = $i * $i;
            }

            """, breakpoints: [["line": 3, "condition": "$i == 3"]])
        defer { try? FileManager.default.removeItem(at: session.dir) }
        var thread: Int?
        thread = await firstStop(session.events)
        let frames = StackFrame.parseAll(try await session.client.request("stackTrace", arguments: ["threadId": .int(try #require(thread))]))
        let value = try await session.client.request("evaluate", arguments: ["expression": "$i", "frameId": .int(frames[0].id), "context": "hover"])
        #expect(value["result"]?.stringValue == "3")
        await session.client.shutdown()
    }
}

@Suite struct PHPDebugAdapterTests {
    /// Unpacks a local VSIX (set PHPIDE_PHP_DEBUG_VSIX) into a temp folder.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHPIDE_PHP_DEBUG_VSIX"] != nil))
    func installsFromAVSIX() async throws {
        let vsix = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHPIDE_PHP_DEBUG_VSIX"]!)
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-adapter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(PHPDebugAdapter.installedScript(in: base) == nil)
        let script = try await PHPDebugAdapter.install(into: base, from: vsix)
        #expect(script.lastPathComponent == "phpDebug.js")
        #expect(PHPDebugAdapter.installedScript(in: base) == script)
    }

    @Test func launchArgumentsLoadXdebugForTheRun() {
        let args = PHPDebugAdapter.launchArguments(program: "/p/main.php", cwd: "/p", php: "/bin/php",
                                                   xdebug: .installed(path: "/e/xdebug.so"), arguments: ["a b"], environment: ["K": "V"])
        #expect(args["program"]?.stringValue == "/p/main.php" && args["port"]?.intValue == 0)
        #expect(args["runtimeArgs"]?.arrayValue?.first?.stringValue == "-dzend_extension=/e/xdebug.so")
        #expect(args["runtimeArgs"]?.arrayValue?.last?.stringValue == "-dxdebug.client_port=${port}")
        #expect(args["args"]?[0]?.stringValue == "a b" && args["env"]?["K"]?.stringValue == "V")
        #expect(PHPDebugAdapter.evaluateContext(forWatch: "$user->profile['name']") == "watch")
        #expect(PHPDebugAdapter.evaluateContext(forWatch: " $items[0] ") == "watch")
        #expect(PHPDebugAdapter.evaluateContext(forWatch: "$a['x'] * 10") == "repl")
        #expect(PHPDebugAdapter.evaluateContext(forWatch: "count($items)") == "repl")
        let listen = PHPDebugAdapter.listenArguments(port: 9003)
        #expect(listen["program"] == nil && listen["port"]?.intValue == 9003)
    }
}
