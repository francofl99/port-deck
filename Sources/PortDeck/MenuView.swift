import SwiftUI

struct StatusDot: View {
    let status: Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .running: .green
        case .starting, .stopping: .yellow
        case .foreign: .orange
        case .failed: .red
        case .stopped: .secondary.opacity(0.4)
        }
    }
}

struct MenuView: View {
    @Environment(Deck.self) private var deck
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PortDeck").font(.headline)
                Spacer()
                Text(deck.activeCount == 1 ? "1 activo" : "\(deck.activeCount) activos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            Divider()
            if deck.projects.isEmpty {
                Text("Todavía no hay proyectos.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(deck.projects) { ProjectRow(project: $0, openMain: openMain) }
            }
            Divider()
            MenuAction(title: "Agregar proyecto…", systemImage: "plus.circle", action: {
                openMain(nil)
                DispatchQueue.main.async { deck.pickAndAdd() }
            })
            MenuAction(title: "Abrir PortDeck…", systemImage: "macwindow", action: { openMain(nil) })
            MenuAction(title: "Salir", systemImage: "power", action: { NSApp.terminate(nil) })
                .padding(.bottom, 4)
        }
        .frame(width: 380)
    }

    private func openMain(_ selection: SidebarItem?) {
        if let selection { deck.selection = selection }
        openWindow(id: "main")
        NSApp.activate()
    }
}

private struct MenuAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(hover ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .onHover { hover = $0 }
    }
}

private struct ProjectRow: View {
    @Environment(Deck.self) private var deck
    let project: Project
    let openMain: (SidebarItem?) -> Void
    @State private var askingPort = false
    @State private var portText = ""

    var body: some View {
        let status = deck.status(of: project)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                StatusDot(status: status)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).lineLimit(1)
                    Text(status.caption(defaultPort: project.port))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(verbatim: ":\(status.port ?? project.port)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                actions(status)
            }
            if let error = deck.errors[project.id] {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if askingPort {
                HStack(spacing: 6) {
                    Text("Puerto").font(.caption).foregroundStyle(.secondary)
                    TextField("", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onSubmit(startOnOtherPort)
                    Button("Arrancar", action: startOnOtherPort)
                        .disabled(Int(portText) == nil)
                    Button("Cancelar") { askingPort = false }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func actions(_ status: Status) -> some View {
        HStack(spacing: 2) {
            if status.isActive {
                IconButton(systemImage: "stop.fill", help: "Detener") { deck.stop(project) }
                    .disabled(status == .stopping)
            } else {
                IconButton(systemImage: "play.fill", help: "Arrancar en :\(project.port)") { deck.start(project) }
            }
            IconButton(systemImage: "safari", help: "Abrir en el navegador") { deck.open(project) }
                .disabled(status.port == nil)
            Menu {
                Button("Arrancar en otro puerto…") {
                    portText = String(deck.freePort(after: project.port))
                    askingPort = true
                }
                .disabled(status.isActive)
                Button("Ver log") { deck.openLog(project) }
                Divider()
                Button("Configurar…") { openMain(.project(project.id)) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func startOnOtherPort() {
        guard let port = Int(portText) else { return }
        deck.start(project, on: port)
        askingPort = false
    }
}

private struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(width: 22, height: 20)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
