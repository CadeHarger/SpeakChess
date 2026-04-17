import SwiftUI
import SwiftData
import Darwin

@main
struct SpeakChessApp: App {

    init() {
        // Writing to a closed engine pipe delivers SIGPIPE, which by default
        // terminates the process.  Ignoring it converts pipe writes on a dead
        // connection into a recoverable EPIPE errno instead of a fatal crash.
        // This covers both AnalysisManager and EngineManager engine restarts.
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: SavedGame.self)
    }
}
