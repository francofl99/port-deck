import AppKit
import Observation

enum Status: Equatable {
    case stopped
    case starting(Int)
    case running(Int)
    case stopping
    case foreign(Int, Listener) // el puerto lo ocupa un proceso que PortDeck no lanzó
    case failed(Int32)

    var isActive: Bool {
        switch self {
        case .starting, .running, .stopping: true
        default: false
        }
    }

    var port: Int? {
        switch self {
        case .starting(let p), .running(let p), .foreign(let p, _): p
        default: nil
        }
    }

    func caption(defaultPort: Int) -> String {
        switch self {
        case .stopped: "Inactivo"
        case .starting(let p): "Arrancando en :\(p)…"
        case .running(let p): p == defaultPort ? "Activo" : "Activo en otro puerto"
        case .stopping: "Deteniendo…"
        case .foreign(_, let l): "Puerto en uso por \(l.command)"
        case .failed(let code): "Se detuvo con error (código \(code))"
        }
    }
}

// Lo lanzado sobrevive a un cierre inesperado de la app: se guarda para retomarlo al volver.
struct Run: Codable {
    var pgid: Int32
    var port: Int
    var stopping = false
}

enum SidebarItem: Hashable {
    case project(UUID)
    case general
}

@MainActor @Observable
final class Deck {
    static let shared = Deck()

    private(set) var projects: [Project]
    private(set) var listening: [Int: Listener] = [:]
    private(set) var runs: [UUID: Run]
    private(set) var failures: [UUID: Int32] = [:]
    var errors: [UUID: String] = [:]
    var selection: SidebarItem? = .general

    @ObservationIgnored private var exitStatus: [UUID: Int32] = [:]
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var scanned = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let environment = Task.detached { ShellEnvironment.resolve() }

    private init() {
        projects = Paths.load([Project].self, from: Paths.projects) ?? []
        runs = (Paths.load([UUID: Run].self, from: Paths.runtime) ?? [:])
            .filter { Spawner.alive(group: $0.value.pgid) }
            .mapValues { Run(pgid: $0.pgid, port: $0.port) }
        saveRuntime()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { Deck.shared.tick() }
        }
        tick()
    }

    var activeCount: Int { runs.count }

    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }

    func status(of project: Project) -> Status {
        if let run = runs[project.id] {
            if run.stopping { return .stopping }
            return listening[run.port] != nil ? .running(run.port) : .starting(run.port)
        }
        if let listener = listening[project.port] { return .foreign(project.port, listener) }
        if let code = failures[project.id] { return .failed(code) }
        return .stopped
    }

    func freePort(after port: Int) -> Int {
        var candidate = port + 1
        while listening[candidate] != nil || runs.values.contains(where: { $0.port == candidate }) { candidate += 1 }
        return candidate
    }

    // MARK: - Proyectos

    func pickAndAdd() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Agregar"
        panel.message = "Elegí la carpeta del proyecto"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        add(folder: folder)
    }

    @discardableResult
    func add(folder: URL) -> Project {
        let guess = Project.guess(in: folder)
        var port = guess.port
        while projects.contains(where: { $0.port == port }) { port += 1 }
        let project = Project(
            name: folder.lastPathComponent,
            directory: (folder.path as NSString).abbreviatingWithTildeInPath,
            command: guess.command,
            port: port
        )
        projects.append(project)
        saveProjects()
        selection = .project(project.id)
        return project
    }

    func update(_ project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i] = project
        saveProjects()
    }

    func remove(_ id: UUID) {
        if let project = project(id) { stop(project) }
        projects.removeAll { $0.id == id }
        failures[id] = nil
        errors[id] = nil
        saveProjects()
        if selection == .project(id) { selection = .general }
    }

    // MARK: - Procesos

    func start(_ project: Project, on port: Int? = nil) {
        let port = port ?? project.port
        errors[project.id] = nil
        guard runs[project.id] == nil else { return }
        if let listener = listening[port] {
            errors[project.id] = "El puerto \(port) está en uso por \(listener.command) (pid \(listener.pid))."
            return
        }
        guard !project.command.trimmingCharacters(in: .whitespaces).isEmpty else {
            errors[project.id] = "Falta el comando de arranque."
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.expandedDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            errors[project.id] = "La carpeta \(project.directory) no existe."
            return
        }
        Task {
            var env = await environment.value
            env["PORT"] = String(port)
            launch(project, port: port, environment: env)
        }
    }

    private func launch(_ project: Project, port: Int, environment: [String: String]) {
        guard runs[project.id] == nil else { return }
        let log = Paths.log(project.id)
        let command = project.command(on: port)
        do {
            try FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
            Self.append("\n── \(Date().formatted()) · :\(port) · \(command)\n", to: log)
            let pid = try Spawner.spawn(
                command: command, directory: project.expandedDirectory, environment: environment, log: log
            )
            runs[project.id] = Run(pgid: pid, port: port)
            failures[project.id] = nil
            saveRuntime()
        } catch {
            errors[project.id] = "No se pudo arrancar: \(error.localizedDescription)"
        }
    }

    func stop(_ project: Project) {
        guard var run = runs[project.id], !run.stopping else { return }
        run.stopping = true
        runs[project.id] = run
        kill(-run.pgid, SIGTERM)
        let group = run.pgid
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if Spawner.alive(group: group) { kill(-group, SIGKILL) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.tick() }
    }

    func stopAll(wait: TimeInterval) {
        let groups = runs.values.map(\.pgid)
        groups.forEach { kill(-$0, SIGTERM) }
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline, groups.contains(where: { waitpid($0, nil, WNOHANG); return Spawner.alive(group: $0) }) {
            usleep(100_000)
        }
        groups.filter { Spawner.alive(group: $0) }.forEach { kill(-$0, SIGKILL) }
        runs = [:]
        saveRuntime()
    }

    func open(_ project: Project) {
        let port = status(of: project).port ?? project.port
        if let url = project.url(on: port) { NSWorkspace.shared.open(url) }
    }

    func openLog(_ project: Project) {
        let log = Paths.log(project.id)
        if FileManager.default.fileExists(atPath: log.path) { NSWorkspace.shared.open(log) }
    }

    // Un proceso hijo que terminó queda zombie y su grupo parece vivo hasta recogerlo con waitpid.
    private func tick() {
        var changed = false
        for (id, run) in runs {
            var status: Int32 = 0
            if waitpid(run.pgid, &status, WNOHANG) == run.pgid { exitStatus[id] = status }
            guard !Spawner.alive(group: run.pgid) else { continue }
            runs[id] = nil
            changed = true
            if let status = exitStatus.removeValue(forKey: id), !run.stopping, status & 0x7f == 0 {
                let code = (status >> 8) & 0xff
                if code != 0 { failures[id] = code }
            }
        }
        if changed { saveRuntime() }
        guard !scanning else { return }
        scanning = true
        Task.detached {
            let found = PortScanner.scan()
            await MainActor.run { Deck.shared.scanFinished(found) }
        }
    }

    // El auto-arranque espera al primer escaneo, si no un puerto ocupado pasa inadvertido.
    private func scanFinished(_ found: [Int: Listener]) {
        listening = found
        scanning = false
        guard !scanned else { return }
        scanned = true
        for project in projects where project.startWithApp && runs[project.id] == nil {
            start(project)
        }
    }

    private func saveProjects() { Paths.write(projects, to: Paths.projects) }
    private func saveRuntime() { Paths.write(runs, to: Paths.runtime) }

    private static func append(_ text: String, to url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
    }
}
