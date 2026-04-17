import Foundation
import ChessKit
import ChessKitEngine

// MARK: - Public types

/// A single engine PV line returned by analysis.
struct AnalysisLine: Identifiable {
    let id: Int             // 1-based MultiPV index
    let score: AnalysisScore
    let depth: Int
    let pvSANs: [String]    // Principal variation in SAN notation
}

/// Evaluation score normalised to White's perspective.
/// Positive = White advantage, negative = Black advantage.
enum AnalysisScore {
    case centipawns(Double)
    case mate(Int)           // positive → White mates in N; negative → Black mates in N

    /// Human-readable string, e.g. "+1.5", "-0.3", "M4", "-M2"
    var displayString: String {
        switch self {
        case .centipawns(let cp):
            let pawns = cp / 100.0
            return pawns >= 0 ? String(format: "+%.1f", pawns) : String(format: "%.1f", pawns)
        case .mate(let n):
            return n > 0 ? "M\(n)" : "-M\(-n)"
        }
    }

    /// 0.0 = total Black advantage · 0.5 = equal · 1.0 = total White advantage.
    /// Used to position the evaluation bar.
    var barFraction: Double {
        switch self {
        case .centipawns(let cp):
            return 0.5 + atan(cp / 300.0) / .pi
        case .mate(let n):
            return n > 0 ? 0.96 : 0.04
        }
    }
}

// MARK: - AnalysisManager

/// Manages a dedicated Stockfish instance for post-game position analysis.
///
/// Call `startEngine()` once when the review view appears, then call
/// `analyze(fen:upToIndex:)` whenever the position changes.
/// The `lines` property is updated in real-time as the engine searches deeper.
@MainActor
final class AnalysisManager: ObservableObject {

    @Published private(set) var lines: [AnalysisLine] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var currentDepth: Int = 0
    @Published private(set) var isEngineReady = false

    static let multiPVCount = 3
    static let searchDepth  = 18
    static let maxPVMoves   = 6   // Number of PV moves shown per line

    /// The full SAN move list of the game being reviewed.
    /// Used to reconstruct the board for PV → SAN conversion.
    private let gameSANs: [String]

    private let engine = Engine(type: .stockfish)
    private var currentTask: Task<Void, Never>?

    init(gameSANs: [String]) {
        self.gameSANs = gameSANs
    }

    // MARK: - Lifecycle

    /// Marks the analysis engine as available for use.
    /// Actual engine start-up is deferred to the first `runSearch` call so
    /// that each search gets a guaranteed-fresh AsyncStream with no stale data.
    func startEngine() async {
        isEngineReady = true
    }

    func stopEngine() async {
        cancelAnalysis()
        if await engine.isRunning {
            await engine.stop()
        }
        isEngineReady = false
    }

    // MARK: - Analysis control

    /// Starts (or restarts) analysis at the given FEN.
    /// `upToIndex` is the number of game moves already applied — used to rebuild
    /// the board for converting engine LAN output into readable SAN notation.
    func analyze(fen: String, upToIndex: Int) {
        guard isEngineReady else { return }
        currentTask?.cancel()
        currentTask = nil
        lines = []
        isAnalyzing = true
        currentDepth = 0

        let index = upToIndex
        currentTask = Task {
            await runSearch(fen: fen, upToIndex: index)
        }
    }

    func cancelAnalysis() {
        currentTask?.cancel()
        currentTask = nil
        isAnalyzing = false
    }

    // MARK: - Search loop

    private func runSearch(fen: String, upToIndex: Int) async {
        // Debounce: absorb rapid navigation taps so the engine only restarts
        // after the user has settled on a position for 300 ms.
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            isAnalyzing = false
            return
        }

        guard !Task.isCancelled else {
            isAnalyzing = false
            return
        }

        // Stop any currently-running engine so its AsyncStream is cleared.
        // Each search must own an exclusive stream; sharing one across concurrent
        // Task instances is undefined behaviour for AsyncStream.
        if await engine.isRunning {
            await engine.stop()
        }

        guard !Task.isCancelled else {
            isAnalyzing = false
            return
        }

        await engine.start()

        guard let stream = await engine.responseStream else {
            isAnalyzing = false
            return
        }

        // Drain the engine's internal setup responses (uciok, id, readyok …).
        // Waiting for the first readyok also guarantees that isRunning == true
        // before we send setoption commands — commands sent while isRunning == false
        // are silently dropped by ChessKitEngine.
        for await response in stream {
            guard !Task.isCancelled else {
                isAnalyzing = false
                return
            }
            if case .readyok = response { break }
        }

        guard !Task.isCancelled else {
            isAnalyzing = false
            return
        }

        // Configure analysis options now that isRunning == true.
        await configureEngineOptions()

        // Check cancellation between every await from here on: stopEngine() may have
        // run while we were suspended, killing the engine pipe.  Sending .isready to
        // a closed pipe causes SIGPIPE even though ChessKitEngine normally guards
        // against writes when isRunning == false (isready/uci are exempt from that guard).
        guard !Task.isCancelled else { isAnalyzing = false; return }
        await engine.send(command: .position(.fen(fen)))

        guard !Task.isCancelled else { isAnalyzing = false; return }
        await engine.send(command: .isready)

        var goSent = false
        var infoBuffer: [Int: EngineResponse.Info] = [:]
        var lastReportedDepth = 0

        for await response in stream {
            guard !Task.isCancelled else { break }

            switch response {
            case .readyok where !goSent:
                // This readyok confirms our position command was processed.
                await engine.send(command: .go(depth: Self.searchDepth))
                goSent = true

            case .info(let info) where goSent:
                guard info.score != nil, let pvLANs = info.pv, !pvLANs.isEmpty else { continue }
                let mpv = info.multipv ?? 1
                infoBuffer[mpv] = info

                // Throttle UI updates to once per depth increment
                if let d = info.depth, d > lastReportedDepth {
                    lastReportedDepth = d
                    currentDepth = d
                    lines = buildLines(from: infoBuffer, upToIndex: upToIndex)
                }

            case .bestmove(_, _) where goSent:
                // Final result: ensure lines reflect the deepest completed search
                lines = buildLines(from: infoBuffer, upToIndex: upToIndex)
                isAnalyzing = false
                return

            default:
                break
            }
        }

        if !Task.isCancelled {
            isAnalyzing = false
        }
    }

    // MARK: - Engine configuration

    private func configureEngineOptions() async {
        // NNUE evaluation files must be set before any search; omitting them
        // causes an immediate engine crash on the first position evaluation.
        if let mainNet = bundledResourceURL(named: "nn-1111cefa1111", ext: "nnue") {
            await engine.send(command: .setoption(id: "EvalFile", value: mainNet.path))
        }
        if let smallNet = bundledResourceURL(named: "nn-37f18f62d772", ext: "nnue") {
            await engine.send(command: .setoption(id: "EvalFileSmall", value: smallNet.path))
        }
        await engine.send(command: .setoption(id: "Skill Level", value: "20"))
        await engine.send(command: .setoption(id: "MultiPV", value: "\(Self.multiPVCount)"))
    }

    private func bundledResourceURL(named name: String, ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        guard let root = Bundle.main.resourceURL else { return nil }
        let target = "\(name).\(ext)"
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == target { return url }
        }
        return nil
    }

    // MARK: - Result construction

    private func buildLines(from buffer: [Int: EngineResponse.Info], upToIndex: Int) -> [AnalysisLine] {
        buffer.sorted { $0.key < $1.key }.compactMap { mpvIdx, info in
            buildLine(mpvIndex: mpvIdx, info: info, upToIndex: upToIndex)
        }
    }

    private func buildLine(mpvIndex: Int, info: EngineResponse.Info, upToIndex: Int) -> AnalysisLine? {
        guard let rawScore = info.score,
              let pvLANs = info.pv, !pvLANs.isEmpty,
              let depth = info.depth else { return nil }

        // Determine side to move: even upToIndex = White to move (standard start with White first)
        let whiteToMove = (upToIndex % 2 == 0)

        let score: AnalysisScore
        if let mate = rawScore.mate {
            score = .mate(whiteToMove ? mate : -mate)
        } else if let cp = rawScore.cp {
            score = .centipawns(whiteToMove ? cp : -cp)
        } else {
            return nil
        }

        let pvSANs = convertPVToSAN(pvLANs: pvLANs, upToIndex: upToIndex)
        return AnalysisLine(id: mpvIndex, score: score, depth: depth, pvSANs: pvSANs)
    }

    // MARK: - LAN → SAN conversion

    /// Rebuilds the board from `gameSANs[0..<upToIndex]`, then applies each PV
    /// LAN move to collect SAN strings the player can read.
    private func convertPVToSAN(pvLANs: [String], upToIndex: Int) -> [String] {
        // Rebuild analysis position
        var board = Board()
        for i in 0..<min(upToIndex, gameSANs.count) {
            if let move = Move(san: gameSANs[i], position: board.position) {
                _ = board.move(pieceAt: move.start, to: move.end)
                if let promoted = move.promotedPiece, case .promotion(let pm) = board.state {
                    _ = board.completePromotion(of: pm, to: promoted.kind)
                }
            }
        }

        // Walk the PV
        var sans: [String] = []
        for lan in pvLANs.prefix(Self.maxPVMoves) {
            guard lan.count >= 4 else { break }
            let start = Square(String(lan.prefix(2)))
            let end   = Square(String(lan.dropFirst(2).prefix(2)))
            guard let move = board.move(pieceAt: start, to: end) else { break }

            if case .promotion(let pm) = board.state {
                let kindChar = lan.count == 5 ? lan.last : nil
                let kind = kindChar.flatMap { Piece.Kind(rawValue: String($0).uppercased()) } ?? .queen
                let comp = board.completePromotion(of: pm, to: kind)
                sans.append(comp.san)
            } else {
                sans.append(move.san)
            }
        }
        return sans
    }
}
