import SwiftUI
import ChessKit

struct SettingsView: View {

    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("voiceRate")    private var voiceRate    = 0.5
    @AppStorage("boardTheme")   private var boardThemeRaw = "classic"

    private var selectedTheme: BoardTheme {
        BoardTheme(rawValue: boardThemeRaw) ?? .classic
    }

    var body: some View {
        Form {
            // MARK: Sound
            Section("Sound") {
                Toggle("Sound Effects", isOn: $soundEnabled)
            }

            // MARK: Voice
            Section {
                LabeledContent("Speaking Speed") {
                    Slider(value: $voiceRate, in: 0.2...0.9, step: 0.05)
                        .frame(maxWidth: 200)
                }
                HStack {
                    Text("Slow")
                    Spacer()
                    Text("Fast")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } header: {
                Text("Voice")
            } footer: {
                Text("Controls how fast moves are read aloud. Changes apply to the next spoken move.")
            }

            // MARK: Board
            Section {
                Picker("Theme", selection: $boardThemeRaw) {
                    ForEach(BoardTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                ChessBoardView(
                    board: Board(),
                    playerColor: .white,
                    selectedSquare: Square("e2"),
                    legalMoveSquares: [Square("e3"), Square("e4")],
                    lastMove: nil,
                    onSquareTap: { _ in }
                )
                .frame(height: 180)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("Board")
            } footer: {
                Text("Theme applies everywhere in the app. The preview above updates instantly.")
            }

            // MARK: About
            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Engine", value: "Stockfish 16 (on-device)")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
