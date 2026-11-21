import SwiftUI
import AppKit

/// Diese App hat nur ein Fenster und keinen Sinn ohne es. Das Schließen des Fensters
/// (rotes Symbol) soll die App deshalb wirklich beenden – inklusive Netzwerk-Reset –
/// statt sie unsichtbar im Hintergrund weiterlaufen zu lassen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct NetAutoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("NetMatch") {
            ContentView()
                .frame(minWidth: 880, minHeight: 640)
        }
    }
}

// MARK: - Hauptansicht

struct ContentView: View {
    @StateObject private var e = Engine()
    @StateObject private var setup = SetupManager()
    @State private var showSetup = false

    var body: some View {
        NavigationSplitView {
            AdapterSidebar(e: e)
        } detail: {
            DetailView(e: e, setup: setup, showSetup: $showSetup)
        }
        .sheet(isPresented: $showSetup) {
            SetupWizard(setup: setup, isPresented: $showSetup)
        }
        .animation(.easeInOut(duration: 0.2), value: setup.allGood)
        .task {
            setup.refresh()
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !setup.allGood { showSetup = true }
        }
    }
}

// MARK: - Seitenleiste

struct AdapterSidebar: View {
    @ObservedObject var e: Engine
    @AppStorage("showAll") private var showAll = true

    private var connected: [Port] { e.ports.filter { e.portUp[$0.device] == true } }
    private var others: [Port] { e.ports.filter { e.portUp[$0.device] != true } }

    var body: some View {
        List(selection: Binding<String?>(
            get: { e.selected },
            set: { if let v = $0 { e.selected = v } }
        )) {
            Section("Angeschlossen") {
                if connected.isEmpty {
                    Text("Kein Adapter mit Kabel")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(connected) { p in
                    AdapterRow(port: p, up: true, ip: e.portIP[p.device])
                        .tag(p.service)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            if showAll {
                Section("Nicht verbunden") {
                    ForEach(others) { p in
                        AdapterRow(port: p, up: false, ip: nil)
                            .tag(p.service)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Toggle("Nicht verbundene zeigen", isOn: $showAll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button { e.refreshPorts() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Adapterliste aktualisieren")
            }
            .padding(10)
            .background(.bar)
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 280)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: e.portUp)
    }
}

struct AdapterRow: View {
    let port: Port
    let up: Bool
    let ip: String?

    private var symbol: String {
        let n = port.service.lowercased()
        if n.contains("wi-fi") || n.contains("wlan") { return "wifi" }
        if n.contains("bluetooth") { return "dot.radiowaves.left.and.right" }
        if n.contains("thunderbolt") { return "bolt.horizontal" }
        return "cable.connector"
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(up ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12))
                Image(systemName: symbol)
                    .foregroundStyle(up ? Color.green : Color.secondary)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(port.service)
                    .fontWeight(up ? .semibold : .regular)
                    .lineLimit(1)
                Text(up ? "\(port.device) · \(ip ?? "keine IP")" : "\(port.device) · kein Kabel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if up { Circle().fill(Color.green).frame(width: 8, height: 8) }
        }
        .opacity(up ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.25), value: up)
        .padding(.vertical, 2)
    }
}

// MARK: - Detailansicht

extension View {
    func card() -> some View {
        self.padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct DetailView: View {
    @ObservedObject var e: Engine
    @ObservedObject var setup: SetupManager
    @Binding var showSetup: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !setup.allGood { setupBanner }
                header
                automation
                profiles
                protocolCard
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem {
                Button { showSetup = true } label: {
                    Label("Einrichtung", systemImage: "wrench.and.screwdriver")
                }
                .help("Einrichtungs-Assistent öffnen")
            }
        }
    }

    private var setupBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
            Text("Die Einrichtung ist noch nicht abgeschlossen.").font(.callout)
            Spacer()
            Button("Einrichten …") { showSetup = true }
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.5)))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(e.currentPort?.service ?? "Kein Adapter gewählt")
                    .font(.title.bold())
                HStack(spacing: 6) {
                    Circle().fill(e.linkUp ? Color.green : Color.gray).frame(width: 9, height: 9)
                    Text(e.linkUp ? "Kabel verbunden" : "Kein Kabel")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Aktuelle IP").font(.caption).foregroundStyle(.secondary)
                Text(e.currentIP)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
            }
        }
        .card()
    }

    private var automation: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatik").font(.headline)
                    Text("Erkennt beim Anstecken die Einstellung des Geräts und stellt den Adapter passend ein.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { e.autoOn }, set: { e.setAuto($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
            }
            HStack(spacing: 8) {
                Image(systemName: e.autoOn ? "antenna.radiowaves.left.and.right" : "power")
                Text(e.status)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(e.autoOn ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill((e.autoOn ? Color.accentColor : Color.secondary).opacity(0.12))
            )

            Divider()

            HStack {
                Stepper("Lauschzeit: \(e.listenSeconds) s", value: $e.listenSeconds, in: 3...30)
                Spacer()
                Button("Auf DHCP zurücksetzen") { e.resetToDHCP() }
                Button("Jetzt konfigurieren") { e.runSequence() }
                    .buttonStyle(.borderedProminent)
                    .disabled(e.currentPort == nil)
            }
        }
        .card()
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feste Profile").font(.headline)
                    Text("Werden der Reihe nach probiert, wenn Erkennung und DHCP scheitern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { e.importProfiles() } label: { Image(systemName: "square.and.arrow.down") }
                    .help("Profile aus Datei importieren")
                Button { e.exportProfiles() } label: { Image(systemName: "square.and.arrow.up") }
                    .help("Profile in Datei exportieren – z. B. um sie an Kollegen weiterzugeben")
                    .disabled(e.profiles.isEmpty)
                Button { e.profiles.append(StaticProfile()) } label: {
                    Label("Profil", systemImage: "plus")
                }
            }
            if e.profiles.isEmpty {
                Text("Noch keine Profile angelegt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("Name"); Text("IP"); Text("Maske"); Text("Router"); Text("Test-IP")
                        Color.clear.frame(width: 20, height: 1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach($e.profiles) { $p in
                        GridRow {
                            TextField("", text: $p.name)
                            TextField("", text: $p.ip)
                            TextField("", text: $p.mask)
                            TextField("", text: $p.router)
                            TextField("", text: $p.probeIP)
                            Button(role: .destructive) {
                                e.profiles.removeAll { $0.id == p.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .card()
    }

    private var protocolCard: some View {
        DisclosureGroup("Protokoll") {
            ScrollView {
                Text(e.logLines.isEmpty ? "Noch keine Einträge." : e.logLines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(height: 150)
            .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .card()
    }
}
