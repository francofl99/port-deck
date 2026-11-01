import Darwin
import Foundation

enum ShellEnvironment {
    // Una app abierta al iniciar sesión hereda el PATH mínimo de launchd, sin nvm ni Homebrew:
    // se copia el entorno de un shell interactivo, como hace VS Code. El marcador separa
    // lo que imprima el rc del shell de la salida de `env`.
    static func resolve() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let marker = "__PORTDECK_ENV__"
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: env["SHELL"] ?? "/bin/zsh")
        shell.arguments = ["-ilc", "printf \(marker); env -0"]
        let out = Pipe()
        shell.standardOutput = out
        shell.standardError = FileHandle.nullDevice
        shell.standardInput = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return env }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if shell.isRunning { shell.terminate() } }
        let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        shell.waitUntilExit()
        guard let start = output.range(of: marker) else { return env }
        for entry in output[start.upperBound...].split(separator: "\0") {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        for key in ["PWD", "OLDPWD", "SHLVL", "_"] { env[key] = nil }
        return env
    }
}

enum Spawner {
    // Cada proyecto arranca en su propio grupo de procesos: detenerlo señala al grupo entero,
    // si no `npm` muere y node/esbuild quedan vivos ocupando el puerto.
    static func spawn(command: String, directory: String, environment: [String: String], log: URL) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addchdir_np(&actions, directory)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)

        let argv = ["/bin/zsh", "-c", command].map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, "/bin/zsh", &actions, &attributes, argv, envp)
        guard rc == 0 else { throw POSIXError(POSIXErrorCode(rawValue: rc) ?? .EIO) }
        return pid
    }

    static func alive(group: pid_t) -> Bool {
        kill(-group, 0) == 0 || errno == EPERM
    }
}

struct Listener: Equatable {
    let pid: Int32
    let command: String
}

enum PortScanner {
    // Sin root lsof sólo ve los procesos del usuario, que son los que interesan acá.
    static func scan() -> [Int: Listener] {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        let out = Pipe()
        lsof.standardOutput = out
        lsof.standardError = FileHandle.nullDevice
        guard (try? lsof.run()) != nil else { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        lsof.waitUntilExit()

        var result: [Int: Listener] = [:]
        var pid: Int32 = 0
        var command = ""
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let value = line.dropFirst()
            switch line.first {
            case "p": pid = Int32(value) ?? 0
            case "c": command = String(value)
            case "n":
                if let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]),
                   result[port] == nil {
                    result[port] = Listener(pid: pid, command: command)
                }
            default: break
            }
        }
        return result
    }
}
