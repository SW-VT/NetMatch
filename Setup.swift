import Foundation
import SwiftUI
import Combine

// MARK: - Einrichtung (ersetzt setup.sh)

@MainActor
final class SetupManager: ObservableObject {
    @Published var sudoOK = false
    @Published var bpfOK = false
    @Published var busy = false
    @Published var message = ""

    var allGood: Bool { sudoOK && bpfOK }

    func refresh() {
        Task {
            let s = await bg {
                shell("/usr/bin/sudo", ["-n", "/usr/sbin/networksetup", "-listallnetworkservices"]).status == 0
            }
            let b = await bg { access("/dev/bpf0", R_OK | W_OK) == 0 }
            sudoOK = s
            bpfOK = b
        }
    }

    func install() { run("install") }
    func remove() { run("remove") }

    private func run(_ mode: String) {
        let user = NSUserName()
        guard user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            message = "Ungewöhnlicher Benutzername – bitte setup.sh im Terminal verwenden."
            return
        }
        busy = true
        message = ""
        let script = Self.scriptText
        Task {
            let result: (Bool, String) = await bg {
                let path = NSTemporaryDirectory() + "netauto-setup.sh"
                do {
                    try script.write(toFile: path, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
                } catch { return (false, "\(error)") }
                let cmd = "/bin/bash '\(path)' \(mode) '\(user)'"
                let osa = "do shell script \"\(cmd)\" with administrator privileges"
                let r = shell("/usr/bin/osascript", ["-e", osa])
                try? FileManager.default.removeItem(atPath: path)
                return (r.status == 0, r.out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            busy = false
            if result.0 {
                message = mode == "remove" ? "Rechte wurden entfernt." : "Einrichtung abgeschlossen."
            } else {
                message = result.1.contains("-128") ? "Abgebrochen." : "Fehlgeschlagen: \(result.1)"
            }
            refresh()
        }
    }

    static let scriptText = #"""
#!/bin/bash
set -e
MODE="$1"
USER_NAME="$2"
SUDOERS=/etc/sudoers.d/netauto
PLIST=/Library/LaunchDaemons/local.netauto.bpf.plist

if [ "$MODE" = "remove" ]; then
  launchctl bootout system "$PLIST" 2>/dev/null || true
  rm -f "$SUDOERS" "$PLIST"
  exit 0
fi

TMP=$(mktemp)
echo "$USER_NAME ALL=(root) NOPASSWD: /usr/sbin/networksetup" > "$TMP"
/usr/sbin/visudo -cf "$TMP"
install -m 0440 -o root -g wheel "$TMP" "$SUDOERS"
rm -f "$TMP"

cat > "$PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.netauto.bpf</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>chgrp admin /dev/bpf*; chmod 660 /dev/bpf*</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"
launchctl bootout system "$PLIST" 2>/dev/null || true
launchctl bootstrap system "$PLIST"
chgrp admin /dev/bpf*
chmod 660 /dev/bpf*
"""#
}

// MARK: - Assistent

struct SetupWizard: View {
    @ObservedObject var setup: SetupManager
    @Binding var isPresented: Bool
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)

            Group {
                switch step {
                case 0: welcome
                case 1: install
                default: done
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            HStack {
                Button("Schließen") { isPresented = false }
                Spacer()
                if step > 0 && step < 2 { Button("Zurück") { step -= 1 } }
                if step == 0 { Button("Weiter") { step = 1 }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
                if step == 1 && setup.allGood { Button("Weiter") { step = 2 }.buttonStyle(.borderedProminent) }
                if step == 2 { Button("Fertig") { isPresented = false }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            }
            .padding(16)
        }
        .frame(width: 540, height: 480)
        .onAppear { setup.refresh(); if setup.allGood { step = 2 } }
        .onChange(of: setup.allGood) { _, good in
            if good && step == 1 { step = 2 }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "cable.connector.horizontal")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Willkommen bei NetMatch").font(.title.bold())
            Text("Damit die App Netzwerkeinstellungen ändern und am Kabel mithören kann, braucht sie einmalig zwei Berechtigungen.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Label("Adapter umstellen: erlaubt nur das Systemprogramm „networksetup“ ohne Passwortabfrage.", systemImage: "slider.horizontal.3")
                Label("Am Kabel mithören: erlaubt Administratoren das Mitlesen von Netzwerkpaketen, damit Geräte erkannt werden.", systemImage: "waveform.path.ecg")
            }
            .font(.callout)
            Text("Du gibst dafür im nächsten Schritt einmal dein Mac-Passwort ein.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var install: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Berechtigungen").font(.title2.bold())
            checkRow("Adapter umstellen", ok: setup.sudoOK)
            checkRow("Am Kabel mithören", ok: setup.bpfOK)
            if !setup.message.isEmpty {
                Text(setup.message).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    setup.install()
                } label: {
                    Label(setup.busy ? "Wird eingerichtet …" : "Jetzt einrichten …", systemImage: "lock.open")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(setup.busy)
                if setup.busy { ProgressView().controlSize(.small) }
            }
            Text("macOS fragt nach deinem Passwort (oder Touch ID).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: setup.allGood ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(setup.allGood ? Color.green : Color.orange)
            Text(setup.allGood ? "Alles bereit" : "Noch nicht vollständig").font(.title.bold())
            Text(setup.allGood
                 ? "Wähle links einen angeschlossenen Adapter und schalte die Automatik ein."
                 : "Es fehlen noch Berechtigungen. Geh einen Schritt zurück und starte die Einrichtung erneut.")
                .foregroundStyle(.secondary)
            if setup.allGood {
                Divider().padding(.vertical, 6)
                Text("Die Rechte lassen sich jederzeit wieder entfernen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Rechte entfernen …", role: .destructive) { setup.remove() }
                    .disabled(setup.busy)
            } else {
                Button("Zurück zur Einrichtung") { step = 1 }
            }
            if !setup.message.isEmpty {
                Text(setup.message).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func checkRow(_ title: String, ok: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(ok ? Color.green : Color.red)
            Text(title).font(.headline)
            Spacer()
            Text(ok ? "eingerichtet" : "fehlt").foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
