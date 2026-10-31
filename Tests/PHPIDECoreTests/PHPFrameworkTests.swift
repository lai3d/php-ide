import Foundation
import Testing
@testable import PHPIDECore

@Suite struct PHPFrameworkTests {
    @Test func parsesLaravelRoutes() {
        let output = #"""
            [{"domain":null,"method":"GET|HEAD","uri":"\/","name":null,"action":"Closure","middleware":["web"]},
             {"domain":null,"method":"GET|HEAD","uri":"users\/{user}","name":"users.show","action":"App\\Http\\Controllers\\UserController@show","middleware":["web"]},
             {"domain":null,"method":"POST","uri":"api\/ping","name":null,"action":"App\\Http\\Controllers\\PingController","middleware":["api"]}]
            """#
        let routes = PHPFramework.laravel.parseRoutes(output)
        #expect(routes.map(\.path) == ["/", "/users/{user}", "/api/ping"])
        #expect(routes[1].name == "users.show" && routes[1].methods == "GET|HEAD")
        #expect(PHPFramework.controller(of: routes[1].action!)! == ("App\\Http\\Controllers\\UserController", "show"))
        #expect(PHPFramework.controller(of: routes[2].action!)! == ("App\\Http\\Controllers\\PingController", nil))
        #expect(PHPFramework.controller(of: "Closure") == nil)
    }

    @Test func parsesSymfonyRoutesAndCommands() {
        let routes = PHPFramework.symfony.parseRoutes(#"""
            {"b_route": {"path": "/b", "method": "POST", "defaults": {"_controller": "App\\Controller\\B::run"}},
             "a_route": {"path": "/a", "method": "ANY", "defaults": {"_controller": "App\\Controller\\A::index"}}}
            """#)
        #expect(routes.map(\.path) == ["/a", "/b"] && routes[0].name == "a_route")
        #expect(PHPFramework.controller(of: routes[1].action!)! == ("App\\Controller\\B", "run"))

        let commands = PHPFramework.parseCommands(#"""
            Deprecated: something
            {"commands": [{"name": "make:model", "description": "Create a model"}, {"name": "_complete", "hidden": true},
                          {"name": "about", "description": "Info"}]}
            """#)
        #expect(commands.map(\.name) == ["about", "make:model"])
    }

    @Test func detectsFrameworksAndFindsClassesThroughPSR4() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-fw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("app/Http"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PHPFramework.detect(in: root) == nil)
        try "".write(to: root.appendingPathComponent("artisan"), atomically: true, encoding: .utf8)
        #expect(PHPFramework.detect(in: root) == .laravel)
        try #"{"autoload": {"psr-4": {"App\\": "app/"}}}"#.write(to: root.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
        try "<?php class Kernel {}".write(to: root.appendingPathComponent("app/Http/Kernel.php"), atomically: true, encoding: .utf8)
        #expect(Composer.file(forClass: "App\\Http\\Kernel", in: root)?.lastPathComponent == "Kernel.php")
        #expect(Composer.file(forClass: "\\Other\\Kernel", in: root)?.lastPathComponent == "Kernel.php")  // by file name
        #expect(Composer.file(forClass: "App\\Missing", in: root) == nil)
    }
}
