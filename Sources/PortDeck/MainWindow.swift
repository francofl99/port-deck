import ServiceManagement
import SwiftUI

struct MainWindow: View {
    @Environment(Deck.self) private var deck

    var body: some View {
        @Bindable var deck = deck
        NavigationSplitView {
            List(selection: $deck.selection) {
                Section("Proyectos") {
                    ForEach(deck.projects) { project in
                        HStack(spacing: 8) {
                            StatusDot(status: deck.status(of: project))
                            Text(project.name).lineLimit(1)
                            Spacer()
                            Text(verbatim: ":\(project.port)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.project(project.id))
                    }
                }
                Section {
                    Label("General", systemImage: "gearshape").tag(SidebarItem.general)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { deck.pickAndAdd() } label: {
                    Label("Agregar proyecto", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            switch deck.selection {
            case .project(let id) where deck.project(id) != nil:
                ProjectEditor(id: id).id(id)
            default:
                GeneralView()
            }
        }
        .toolbar {
            ToolbarItem {
                Button { deck.pickAndAdd() } label: { Label("Agregar proyecto", systemImage: "plus") }
                    .help("Agregar proyecto")
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

private struct ProjectEditor: View {
    @Environment(Deck.self) private var deck
    let id: UUID
    @State private var log = ""
    @State private var confirmRemove = false

    var body: some View {
        if let project = deck.project(id) {
            let binding = Binding(get: { deck.project(id) ?? project }, set: { deck.update($0) })
            let status = deck.status(of: project)
            Form {
                Section {
                    HStack(spacing: 10) {
                        StatusDot(status: status)
                        Text(status.caption(defaultPort: project.port))
                        Spacer()
                        if status.isActive {
                            Button("Detener") { deck.stop(project) }.disabled(status == .stopping)
                        } else {
                            Button("Arrancar") { deck.start(project) }
                        }
                        Button("Abrir") { deck.open(project) }.disabled(status.port == nil)
                    }
                    if let error = deck.errors[id] {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section("Proyecto") {
                    TextField("Nombre", text: binding.name)
                    LabeledContent("Carpeta") {
                        HStack {
                            TextField("", text: binding.directory).labelsHidden()
                            Button("Elegir…") { pickFolder(binding) }
                        }
                    }
                }

                Section {
                    TextField("Comando", text: binding.command, prompt: Text("npm run dev -- --port {PORT}"), axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                    TextField("Puerto por defecto", text: Binding(
                        get: { String(binding.wrappedValue.port) },
                        set: { if let port = Int($0.filter(\.isNumber)) { binding.wrappedValue.port = port } }
                    ))
                    TextField("URL", text: binding.url, prompt: Text("http://localhost:{PORT}"))
                    Toggle("Arrancar al abrir PortDeck", isOn: binding.startWithApp)
                } header: {
                    Text("Arranque")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Se corre con zsh dentro de la carpeta, con el entorno de tu shell. `{PORT}` se reemplaza por el puerto elegido y además se exporta `$PORT`.")
                        Text("Ej.: `npm run dev -- --port {PORT}` · `php artisan serve --port={PORT}` · `npm start` si la app lee `$PORT`.")
                        if !project.command.isEmpty && !project.command.contains("{PORT}") {
                            Text("El comando no usa `{PORT}`: para arrancar en otro puerto la app tiene que leer `$PORT`.")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    ScrollView {
                        Text(log.isEmpty ? "Sin salida todavía." : log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(log.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(height: 180)
                } header: {
                    HStack {
                        Text("Log")
                        Spacer()
                        Button("Abrir en Consola") { deck.openLog(project) }.buttonStyle(.link)
                    }
                }

                Section {
                    Button("Quitar proyecto", role: .destructive) { confirmRemove = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(project.name)
            .task(id: id) {
                while !Task.isCancelled {
                    log = Self.tail(Paths.log(id))
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .confirmationDialog("¿Quitar \(project.name)?", isPresented: $confirmRemove) {
                Button("Quitar", role: .destructive) { deck.remove(id) }
            } message: {
                Text(status.isActive ? "Se detiene y deja de aparecer en PortDeck." : "Deja de aparecer en PortDeck. La carpeta no se toca.")
            }
        }
    }

    private func pickFolder(_ binding: Binding<Project>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: binding.wrappedValue.expandedDirectory)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        binding.wrappedValue.directory = (folder.path as NSString).abbreviatingWithTildeInPath
    }

    private static func tail(_ url: URL, bytes: UInt64 = 24_000) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        handle.seek(toFileOffset: size > bytes ? size - bytes : 0)
        return String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    }
}

private struct GeneralView: View {
    @AppStorage("stopOnQuit") private var stopOnQuit = true
    @State private var login = SMAppService.mainApp.status
    @State private var loginError = ""

    var body: some View {
        Form {
            Section("Inicio") {
                Toggle("Abrir PortDeck al iniciar sesión", isOn: Binding(
                    get: { login == .enabled || login == .requiresApproval },
                    set: setLogin
                ))
                if login == .requiresApproval {
                    HStack {
                        Text("macOS pide aprobarlo en Ítems de inicio.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Abrir Ajustes") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if !loginError.isEmpty {
                    Text(loginError).foregroundStyle(.red)
                }
                Toggle("Detener los proyectos al salir de PortDeck", isOn: $stopOnQuit)
            }
            Section("Archivos") {
                LabeledContent("Proyectos", value: Paths.projects.path)
                LabeledContent("Logs", value: Paths.logs.path)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear { login = SMAppService.mainApp.status }
    }

    private func setLogin(_ on: Bool) {
        loginError = ""
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = error.localizedDescription
        }
        login = SMAppService.mainApp.status
    }
}
