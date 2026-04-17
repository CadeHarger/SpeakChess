import Foundation
import ChessKitEngine
import OSLog

@MainActor
final class EngineManager: ObservableObject {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SpeakChess",
        category: "EngineManager"
    )

    private let engine = Engine(type: .stockfish)

    @Published var isReady = false
    @Published var isThinking = false

    var skillLevel: Int = 10

    // The `go` command sent to Stockfish, tuned per difficulty tier.
    // Lower tiers use a depth cap rather than movetime so the engine truly cannot
    // see more than N plies regardless of hardware speed — depth 1 means it only
    // avoids immediate blunders and plays essentially random-looking moves.
    private var goCommand: EngineCommand {
        switch skillLevel {
        case 0...3:   return .go(depth: 1)          // Beginner  – 1-ply, no tactics
        case 4...7:   return .go(depth: 4)           // Intermediate – sees simple tactics
        case 8...12:  return .go(movetime: 600)      // Advanced
        case 13...17: return .go(movetime: 1500)     // Expert
        default:      return .go(movetime: 3000)     // Master
        }
    }

    /// Hard upper bound on how long requestBestMove will wait for a `bestmove`
    /// response. Sized generously above the search budget to allow for cold-start
    /// latency, NNUE load time, and OS scheduling — but bounded so the game
    /// never locks up if the engine hangs or swallows a message.
    private var searchTimeoutNanoseconds: UInt64 {
        let millis: UInt64
        switch skillLevel {
        case 0...3:   millis = 3_000
        case 4...7:   millis = 5_000
        case 8...12:  millis = 8_000
        case 13...17: millis = 15_000
        default:      millis = 30_000
        }
        return millis * 1_000_000
    }

    func startEngine() async {
        await engine.start()
        await configureEngineOptions()
        isReady = true
    }

    func stopEngine() async {
        await engine.stop()
        isReady = false
        isThinking = false
    }

    /// Sends the current position to the engine and returns the best move in UCI LAN format
    /// (e.g. "e2e4", "e7e8q"). On the first timeout the engine process is fully restarted
    /// (flushing any stuck state) before a single retry. Returns nil only if both attempts fail.
    func requestBestMove(fen: String) async -> String? {
        guard await engine.isRunning else {
            logger.error("engine is not running when requesting move")
            return nil
        }
        isThinking = true

        if let move = await attemptSearch(fen: fen) {
            isThinking = false
            return move
        }

        // First attempt timed out — the engine process may be stuck. Restart it cleanly
        // so the retry gets a fresh UCI session rather than hammering a wedged engine.
        logger.error("first search attempt timed out; restarting engine before retry")
        await engine.stop()
        await engine.start()
        await configureEngineOptions()

        let move = await attemptSearch(fen: fen)
        isThinking = false
        if move == nil {
            logger.error("retry search also failed; engine is unresponsive")
        }
        return move
    }

    // MARK: - Private helpers

    /// Configures NNUE evaluation files. Called on every engine start so restart preserves settings.
    private func configureEngineOptions() async {
        if let mainNet = bundledResourceURL(named: "nn-1111cefa1111", ext: "nnue") {
            await engine.send(command: .setoption(id: "EvalFile", value: mainNet.path))
            logger.debug("configured EvalFile: \(mainNet.path, privacy: .public)")
        } else {
            logger.error("missing Stockfish main NNUE file")
        }
        if let smallNet = bundledResourceURL(named: "nn-37f18f62d772", ext: "nnue") {
            await engine.send(command: .setoption(id: "EvalFileSmall", value: smallNet.path))
            logger.debug("configured EvalFileSmall: \(smallNet.path, privacy: .public)")
        } else {
            logger.error("missing Stockfish small NNUE file")
        }
    }

    /// Executes one search attempt, racing the response loop against the per-tier timeout.
    private func attemptSearch(fen: String) async -> String? {
        logger.debug("requestBestMove fen: \(fen, privacy: .public)")

        await engine.send(command: .stop)
        await engine.send(command: .setoption(id: "Skill Level", value: "\(skillLevel)"))
        await engine.send(command: .position(.fen(fen)))
        await engine.send(command: .isready)

        guard let stream = await engine.responseStream else {
            logger.error("engine response stream unavailable")
            return nil
        }

        let timeoutNs = searchTimeoutNanoseconds
        let move: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask { [weak self] in
                guard let self else { return nil }
                var goSent = false
                for await response in stream {
                    switch response {
                    case .readyok:
                        logger.debug("engine readyok received")
                        await engine.send(command: goCommand)
                        goSent = true
                    case .bestmove(let m, _) where goSent:
                        logger.debug("engine bestmove received: \(m, privacy: .public)")
                        return m
                    default:
                        break
                    }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNs)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
        }

        if move == nil {
            logger.error("search timed out; sending stop")
            await engine.send(command: .stop)
        }
        return move
    }

    private func bundledResourceURL(named name: String, ext: String) -> URL? {
        if let direct = Bundle.main.url(forResource: name, withExtension: ext) {
            return direct
        }

        guard let resourceRoot = Bundle.main.resourceURL else { return nil }
        let targetName = "\(name).\(ext)"
        let enumerator = FileManager.default.enumerator(
            at: resourceRoot,
            includingPropertiesForKeys: nil
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == targetName {
                return url
            }
        }

        return nil
    }
}
