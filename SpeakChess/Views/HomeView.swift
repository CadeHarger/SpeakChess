import SwiftUI
import SwiftData
import ChessKit

struct HomeView: View {

    @Query(sort: \SavedGame.date, order: .reverse) private var allGames: [SavedGame]

    private var ongoingGame: SavedGame? {
        allGames.first { $0.isOngoing }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // App icon / logo area
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.gradient)
                            .frame(width: 100, height: 100)
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 12, y: 6)
                        Text("♟")
                            .font(.system(size: 56))
                    }

                    Text("SpeakChess")
                        .font(.largeTitle.bold())

                    Text("Play chess hands-free with your voice")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                // Primary actions
                VStack(spacing: 12) {
                    NavigationLink {
                        NewGameView()
                    } label: {
                        Label("New Game", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if let ongoing = ongoingGame {
                        NavigationLink {
                            GameView(
                                playerColor: ongoing.isPlayerWhite ? .white : .black,
                                skillLevel: ongoing.skillLevel,
                                resumeGame: ongoing
                            )
                        } label: {
                            HStack {
                                Label("Resume Game", systemImage: "arrow.clockwise")
                                    .font(.headline)
                                Spacer()
                                Text("\(ongoing.moveSANs.count) moves · Skill \(ongoing.skillLevel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    HStack(spacing: 12) {
                        NavigationLink {
                            HistoryView()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.title2)
                                Text("History")
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)

                        NavigationLink {
                            SettingsView()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "gearshape")
                                    .font(.title2)
                                Text("Settings")
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
                    .frame(height: 40)
            }
            .navigationBarHidden(true)
        }
    }

}

#Preview {
    HomeView()
}
