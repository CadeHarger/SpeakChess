import SwiftUI
import ChessKit

struct NewGameView: View {

    @State private var playerColor: Piece.Color = .white
    @State private var skillLevel: Double = 10
    @State private var navigateToGame = false

    private var difficultyLabel: String {
        switch Int(skillLevel) {
        case 0...3:   "Beginner"
        case 4...7:   "Intermediate"
        case 8...12:  "Advanced"
        case 13...17: "Expert"
        default:      "Master"
        }
    }

    private var difficultyColor: Color {
        switch Int(skillLevel) {
        case 0...3:  .green
        case 4...7:  .mint
        case 8...12: .orange
        case 13...17: .red
        default:     .purple
        }
    }

    var body: some View {
        Form {
            // Color selection
            Section("Play as") {
                Picker("Color", selection: $playerColor) {
                    Label("White", systemImage: "circle").tag(Piece.Color.white)
                    Label("Black", systemImage: "circle.fill").tag(Piece.Color.black)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            // Difficulty
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Difficulty")
                        Spacer()
                        Text(difficultyLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(difficultyColor)
                            .contentTransition(.numericText())
                    }
                    Slider(value: $skillLevel, in: 0...20, step: 1)
                        .tint(difficultyColor)
                    HStack {
                        Text("Beginner")
                        Spacer()
                        Text("Master")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Stockfish Skill")
            } footer: {
                Text("Higher levels search deeper and play stronger moves.")
            }

            // Board preview
            Section("Preview") {
                ChessBoardView(
                    board: Board(),
                    playerColor: playerColor,
                    selectedSquare: nil,
                    legalMoveSquares: [],
                    lastMove: nil,
                    onSquareTap: { _ in }
                )
                .frame(height: 200)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        }
        .navigationTitle("New Game")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                NavigationLink("Start") {
                    GameView(playerColor: playerColor, skillLevel: Int(skillLevel))
                }
                .fontWeight(.semibold)
            }
        }
    }
}

#Preview {
    NavigationStack {
        NewGameView()
    }
}
