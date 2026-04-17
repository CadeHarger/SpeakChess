import SwiftUI
import SwiftData

struct HistoryView: View {

    @Query(sort: \SavedGame.date, order: .reverse) private var allGames: [SavedGame]
    @Environment(\.modelContext) private var modelContext

    private var games: [SavedGame] {
        allGames.filter { !$0.isOngoing }
    }

    var body: some View {
        Group {
            if games.isEmpty {
                emptyState
            } else {
                gameList
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !games.isEmpty {
                EditButton()
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Games Yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Completed games will appear here.\nFinish a game to start building your history.")
        }
    }

    private var gameList: some View {
        List {
            ForEach(games) { game in
                NavigationLink {
                    GameReviewView(game: game)
                } label: {
                    GameHistoryRow(game: game)
                }
            }
            .onDelete(perform: deleteGames)
        }
    }

    // MARK: - Actions

    private func deleteGames(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(games[index])
        }
    }
}

// MARK: - Row view

private struct GameHistoryRow: View {

    let game: SavedGame

    var body: some View {
        HStack(spacing: 12) {
            outcomeIcon
            info
            Spacer()
            dateLabel
        }
        .padding(.vertical, 4)
    }

    private var outcomeIcon: some View {
        Image(systemName: game.outcomeSymbol)
            .font(.title2)
            .foregroundStyle(outcomeColor)
            .frame(width: 32)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(game.outcomeDisplay)
                .font(.headline)
                .foregroundStyle(outcomeColor)

            HStack(spacing: 6) {
                Label(game.playerColorDisplay, systemImage: game.isPlayerWhite ? "circle" : "circle.fill")
                Text("·")
                Text("\(game.moveSANs.count) moves")
                Text("·")
                Text("Skill \(game.skillLevel)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var dateLabel: some View {
        Text(game.formattedDate)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.trailing)
    }

    private var outcomeColor: Color {
        switch game.outcomeRaw {
        case "playerWins": return .green
        case "botWins":    return .red
        default:           return .orange
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(for: SavedGame.self, inMemory: true)
}
