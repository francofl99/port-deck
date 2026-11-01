import Foundation

struct Project: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var directory: String
    var command: String
    var port: Int
    var url = ""
    var startWithApp = false

    var expandedDirectory: String { (directory as NSString).expandingTildeInPath }

    func command(on port: Int) -> String {
        command.replacingOccurrences(of: "{PORT}", with: String(port))
    }

    func url(on port: Int) -> URL? {
        let raw = url.isEmpty ? "http://localhost:{PORT}" : url
        return URL(string: raw.replacingOccurrences(of: "{PORT}", with: String(port)))
    }

    // Una primera versión del comando a partir de lo que hay en la carpeta; el usuario lo ajusta.
    static func guess(in folder: URL) -> (command: String, port: Int) {
        let has = { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        if has("artisan") { return ("php artisan serve --port={PORT}", 8000) }
        if has("manage.py") { return ("python manage.py runserver {PORT}", 8000) }
        if let data = try? Data(contentsOf: folder.appendingPathComponent("package.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = json["scripts"] as? [String: String] {
            if let dev = scripts["dev"] {
                if dev.contains("vite") { return ("npm run dev -- --port {PORT}", 5173) }
                if dev.contains("next") { return ("npm run dev -- -p {PORT}", 3000) }
                return ("npm run dev", 3000)
            }
            if scripts["start"] != nil { return ("npm start", 3000) }
        }
        if has("compose.yaml") || has("compose.yml") || has("docker-compose.yml") { return ("docker compose up", 8080) }
        return ("", 3000)
    }
}

enum Paths {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PortDeck")
    static let projects = support.appendingPathComponent("projects.json")
    static let runtime = support.appendingPathComponent("runtime.json")
    static let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PortDeck")

    static func log(_ id: UUID) -> URL { logs.appendingPathComponent("\(id.uuidString).log") }

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? encoder.encode(value).write(to: url, options: .atomic)
    }
}
