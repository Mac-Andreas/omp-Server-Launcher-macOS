// Modernized config.json editor.
// - Sliders with a number box (max_players capped) and dropdowns (gamemode /
//   filterscript from *.amx).
// - Guardrails: no negatives, scroll-wheel does NOT change number fields, port
//   bounded to a valid range.
// - Shows a "config.json not detected" state instead of empty edit fields.
import SwiftUI

struct ConfigView: View {
    @EnvironmentObject private var config: ConfigStore
    @State private var saveError: String?
    @State private var savedFlash = false

    var body: some View {
        ScrollView {
            if config.exists {
                editor
            } else {
                missingState
            }
        }
    }

    private var missingState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 40)).foregroundStyle(Theme.textDim)
            Text("config.json not detected in the server folder")
                .font(.system(size: 15, weight: .semibold))
            Text(ServerEnv.serverDir)
                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            Button("Reload") { config.load() }
                .buttonStyle(PillButtonStyle(kind: .secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    field("Server name") {
                        TextField("", text: $config.serverName).textFieldStyle(.roundedBorder)
                    }
                    // "Server Password" label (renamed in-app per TODO).
                    field("Server Password") {
                        SecureField("", text: $config.password).textFieldStyle(.roundedBorder)
                    }
                    field("Max players") {
                        SliderWithBox(value: $config.maxPlayers, range: 1...1000)
                    }
                    field("Port") {
                        NumberBox(value: $config.port, range: 1...65535)
                            .frame(width: 140)
                    }
                    field("RCON password") {
                        SecureField("", text: $config.rconPassword).textFieldStyle(.roundedBorder)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    field("Gamemode") {
                        ScriptPicker(selection: $config.gamemode, options: config.gamemodeOptions)
                    }
                    field("Filterscript") {
                        ScriptPicker(selection: $config.filterscript, options: config.filterscriptOptions)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Save") {
                    saveError = config.save()
                    if saveError == nil { flashSaved() }
                }
                .buttonStyle(PillButtonStyle(kind: .primary))

                Button("Reload") { config.load() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))

                if savedFlash {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.good).font(.system(size: 12))
                }
                if let e = saveError {
                    Text(e).foregroundStyle(Theme.bad).font(.system(size: 12))
                }
                Spacer()
            }
        }
        .padding(20)
    }

    private func field<V: View>(_ label: String, @ViewBuilder _ control: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
            control()
        }
    }

    private func flashSaved() {
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedFlash = false }
    }
}

// Slider + number box, integer, clamped to range. Scroll wheel disabled.
struct SliderWithBox: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = clamp(Int($0.rounded())) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .tint(Theme.accent)
            NumberBox(value: $value, range: range).frame(width: 100)
        }
    }
    private func clamp(_ v: Int) -> Int { min(max(v, range.lowerBound), range.upperBound) }
}

// Integer text field: no negatives, clamped, and scroll-wheel-proof (TextField
// doesn't respond to scroll, unlike a Stepper/NSStepper) — satisfies the TODO
// guardrail "don't let cursor scroll change the number".
struct NumberBox: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @State private var text: String = ""

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .onAppear { text = String(value) }
            .onChange(of: value) { _, new in text = String(new) }
            .onChange(of: text) { _, new in
                let digits = new.filter(\.isNumber)   // strips '-' and letters
                if let n = Int(digits) {
                    value = min(max(n, range.lowerBound), range.upperBound)
                } else if digits.isEmpty {
                    value = range.lowerBound
                }
                if digits != new { text = digits }
            }
    }
}

// Dropdown of available scripts; allows an empty (none) selection and shows the
// current value even if its file is absent.
struct ScriptPicker: View {
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Picker("", selection: $selection) {
            Text("— none —").tag("")
            if !selection.isEmpty && !options.contains(selection) {
                Text("\(selection) (missing)").tag(selection)
            }
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .tint(Theme.accent)
    }
}
