import Foundation
import Testing
@testable import PHPIDECore

@Suite struct DatabaseSettingsTests {
    let root = URL(fileURLWithPath: "/proj")

    private func settings(_ env: String) -> DatabaseSettings? {
        DatabaseSettings.from(DatabaseSettings.parseDotEnv(env), root: root)
    }

    @Test func laravelVariables() throws {
        let s = try #require(settings("""
            APP_NAME=Shop
            # database
            DB_CONNECTION=pgsql
            DB_HOST=db.local
            DB_PORT=6543
            DB_DATABASE="${APP_NAME}_dev"
            DB_USERNAME=shop
            DB_PASSWORD='p@ss #1'
            """))
        #expect(s.dialect == "postgres" && s.host == "db.local" && s.port == 6543 && s.database == "Shop_dev")
        #expect(s.user == "shop" && s.password == "p@ss #1")
        #expect(s.url() == "postgresql://shop@db.local:6543/Shop_dev")
        #expect(s.url(includingPassword: true) == "postgresql://shop:p%40ss%20%231@db.local:6543/Shop_dev")
    }

    @Test func dbideLinkCarriesTheFullURL() throws {
        let s = try #require(settings("DB_CONNECTION=mysql\nDB_DATABASE=shop\nDB_USERNAME=app\nDB_PASSWORD=a+b&c=d\n"))
        let link = try #require(s.dbideLink(name: "shop (.env)"))
        #expect(link.scheme == "dbide" && link.host == "connect")
        let items = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "url" }?.value == s.url(includingPassword: true))
        #expect(items.first { $0.name == "name" }?.value == "shop (.env)")
        #expect(s.url(includingPassword: true) == "mysql://app:a+b&c=d@127.0.0.1:3306/shop")  // DBIDE splits user info at the last `@`
    }

    @Test func laravelDefaultsAndSQLite() throws {
        let mysql = try #require(settings("DB_CONNECTION=mariadb\nDB_DATABASE=app # main db\n"))
        #expect(mysql.dialect == "mysql" && mysql.host == "127.0.0.1" && mysql.port == 3306 && mysql.database == "app")
        let sqlite = try #require(settings("DB_CONNECTION=sqlite\n"))
        #expect(sqlite.filePath == "/proj/database/database.sqlite" && sqlite.url() == "sqlite:///proj/database/database.sqlite")
        #expect(settings("APP_ENV=local\n") == nil)
    }

    @Test func symfonyDatabaseURL() throws {
        let s = try #require(settings(#"export DATABASE_URL="mysql://app:s%3Acret@127.0.0.1:3307/shop?serverVersion=8.0&charset=utf8mb4""#))
        #expect(s.dialect == "mysql" && s.port == 3307 && s.user == "app" && s.password == "s:cret" && s.database == "shop")
        #expect(s.source == "DATABASE_URL")
        let sqlite = try #require(settings(#"DATABASE_URL="sqlite:///%kernel.project_dir%/var/data.db""#))
        #expect(sqlite.dialect == "sqlite" && sqlite.filePath == "/proj/var/data.db")
    }

    @Test func envLocalOverridesEnv() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "DB_CONNECTION=mysql\nDB_DATABASE=app\n".write(to: dir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "DB_DATABASE=app_local\n".write(to: dir.appendingPathComponent(".env.local"), atomically: true, encoding: .utf8)
        #expect(DatabaseSettings.fromEnvironmentFiles(in: dir)?.database == "app_local")
    }
}
