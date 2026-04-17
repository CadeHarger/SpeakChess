import SwiftUI
import ChessKit

struct GameReviewView: View {

    let game: SavedGame

    @StateObject private var rm: ReviewManager
    @StateObject private var am: AnalysisManager

    @State private var analysisEnabled = false
    @State private var copyConfirmation: String? = nil

    init(game: SavedGame) {
        self.game = game
        self._rm = StateObject(wrappedValue: ReviewManager(moveSANs: game.moveSANs))
        self._am = StateObject(wrappedValue: AnalysisManager(gameSANs: game.moveSANs))
    }

    private var playerColor: Piece.Color { game.isPlayerWhite ? .white : .black }

    var body: some View {
        VStack(spacing: 0) {
            metadataHeader
            board
            moveListBar
            navigationControls
            analysisPanel
        }
        .background(Color(.systemBackground))
        .navigationTitle(game.outcomeDisplay)
        .navigationBarTitleDisplayMode(.inline)
        .gesture(swipeGesture)
        .toolbar { exportToolbarItem }
        .overlay(alignment: .top) {
            if let msg = copyConfirmation {
                Text(msg)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.accentColor))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: copyConfirmation)
        .task { /* Engine started lazily when user enables analysis */ }
        .onDisappear {
            Task { await am.stopEngine() }
        }
        // Re-run analysis whenever the position changes (if enabled)
        .onChange(of: rm.currentMoveIndex) { _, _ in
            if analysisEnabled {
                requestAnalysis()
            }
        }
    }

    // MARK: - Export

    private var exportToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                ShareLink("Share PGN", item: game.pgn)

                Button {
                    copy(game.pgn, label: "PGN copied")
                } label: {
                    Label("Copy Game PGN", systemImage: "doc.on.doc")
                }

                Button {
                    copy(rm.replayBoard.position.fen, label: "FEN copied")
                } label: {
                    Label("Copy Position FEN", systemImage: "pin.square")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    private func copy(_ text: String, label: String) {
        UIPasteboard.general.string = text
        copyConfirmation = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            copyConfirmation = nil
        }
    }

    // MARK: - Swipe navigation

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40, coordinateSpace: .local)
            .onEnded { value in
                if value.translation.width < -40 { rm.stepForward() }
                else if value.translation.width > 40 { rm.stepBack() }
            }
    }

    // MARK: - Header

    private var metadataHeader: some View {
        HStack(spacing: 16) {
            Label(game.playerColorDisplay,
                  systemImage: game.isPlayerWhite ? "circle" : "circle.fill")
                .font(.subheadline)

            Divider().frame(height: 14)

            Label("Skill \(game.skillLevel)", systemImage: "cpu")
                .font(.subheadline)

            Spacer()

            Text(game.formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Board

    private var board: some View {
        ChessBoardView(
            board: rm.replayBoard,
            playerColor: playerColor,
            selectedSquare: nil,
            legalMoveSquares: [],
            lastMove: rm.lastAppliedMove,
            onSquareTap: { _ in }
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // MARK: - Move list

    private var moveListBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if game.moveSANs.isEmpty {
                        Text("No moves")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(movePairs) { pair in
                            HStack(spacing: 3) {
                                Text("\(pair.number).").foregroundStyle(.secondary)
                                moveToken(pair.white, moveIndex: pair.whiteIndex)
                                if let black = pair.black {
                                    moveToken(black, moveIndex: pair.blackIndex)
                                }
                            }
                            .id(pair.id)
                        }
                    }
                }
                .font(.system(.footnote, design: .monospaced))
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
            }
            .onChange(of: rm.currentMoveIndex) { _, newIndex in
                let pairID = max(1, ((newIndex - 1) / 2) + 1)
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(pairID, anchor: .center)
                }
            }
        }
        .frame(height: 44)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func moveToken(_ san: String, moveIndex: Int) -> some View {
        let isActive = moveIndex == rm.currentMoveIndex - 1
        Text(san)
            .fontWeight(isActive ? .bold : .regular)
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            )
    }

    // MARK: - Navigation controls

    private var navigationControls: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Color(.systemFill)
                    Color.accentColor.frame(width: geo.size.width * rm.progressFraction)
                }
            }
            .frame(height: 2)

            HStack(spacing: 0) {
                navButton(icon: "backward.end.fill", action: rm.jumpToStart).disabled(rm.isAtStart)
                navButton(icon: "backward.fill",     action: rm.stepBack).disabled(rm.isAtStart)

                Text("\(rm.currentMoveIndex) / \(rm.totalMoves)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 64)

                navButton(icon: "forward.fill",     action: rm.stepForward).disabled(rm.isAtEnd)
                navButton(icon: "forward.end.fill", action: rm.jumpToEnd).disabled(rm.isAtEnd)
            }
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Analysis panel

    private var analysisPanel: some View {
        VStack(spacing: 0) {
            Divider()
            analysisToggleRow

            if analysisEnabled {
                Divider()
                if am.lines.isEmpty {
                    analysisPlaceholder
                } else {
                    evalBarRow
                    Divider()
                    analysisLines
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .animation(.easeInOut(duration: 0.2), value: analysisEnabled)
        .animation(.easeInOut(duration: 0.15), value: am.lines.count)
    }

    private var analysisToggleRow: some View {
        HStack {
            Image(systemName: "waveform.and.magnifyingglass")
                .foregroundStyle(analysisEnabled ? Color.accentColor : .secondary)
            Text("Stockfish Analysis")
                .font(.subheadline.weight(.medium))
            Spacer()
            if analysisEnabled && am.isAnalyzing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Depth \(am.currentDepth)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else if analysisEnabled && !am.lines.isEmpty {
                Text("Depth \(am.currentDepth)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Toggle("", isOn: $analysisEnabled)
                .labelsHidden()
                .onChange(of: analysisEnabled) { _, enabled in
                    if enabled {
                        Task {
                            await am.startEngine()
                            requestAnalysis()
                        }
                    } else {
                        am.cancelAnalysis()
                        Task { await am.stopEngine() }
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var analysisPlaceholder: some View {
        HStack {
            ProgressView()
            Text("Analysing position…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Eval bar

    private var evalBarRow: some View {
        HStack(spacing: 10) {
            Text("W")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)

            EvalBar(fraction: am.lines.first?.score.barFraction ?? 0.5)

            Text("B")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)

            if let top = am.lines.first {
                Text(top.score.displayString)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(evalColor(top.score))
                    .frame(minWidth: 40, alignment: .trailing)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - PV lines

    private var analysisLines: some View {
        VStack(spacing: 0) {
            ForEach(am.lines) { line in
                AnalysisLineRow(line: line, moveIndex: rm.currentMoveIndex)
                if line.id < am.lines.count {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - Helpers

    private func requestAnalysis() {
        am.analyze(
            fen: rm.replayBoard.position.fen,
            upToIndex: rm.currentMoveIndex
        )
    }

    private func evalColor(_ score: AnalysisScore) -> Color {
        switch score {
        case .mate(let n) where n > 0: return .green
        case .mate(let n) where n < 0: return .red
        case .centipawns(let cp) where cp > 50: return .green
        case .centipawns(let cp) where cp < -50: return .red
        default: return .primary
        }
    }

    // MARK: - Move pair helpers

    private struct MovePair: Identifiable {
        let id: Int
        let number: Int
        let white: String
        let whiteIndex: Int
        let black: String?
        let blackIndex: Int
    }

    private var movePairs: [MovePair] {
        let sans = game.moveSANs
        guard !sans.isEmpty else { return [] }
        var pairs: [MovePair] = []
        var i = 0, moveNum = 1
        while i < sans.count {
            pairs.append(MovePair(
                id: moveNum, number: moveNum,
                white: sans[i], whiteIndex: i,
                black: (i + 1 < sans.count) ? sans[i + 1] : nil,
                blackIndex: (i + 1 < sans.count) ? i + 1 : -1
            ))
            i += 2; moveNum += 1
        }
        return pairs
    }
}

// MARK: - EvalBar

private struct EvalBar: View {

    let fraction: Double   // 0.0 = black wins · 0.5 = equal · 1.0 = white wins

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.label))                  // Black side
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemBackground))       // White side
                    .frame(width: geo.size.width * max(0.04, min(0.96, fraction)))
            }
        }
        .frame(height: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

// MARK: - AnalysisLineRow

private struct AnalysisLineRow: View {

    let line: AnalysisLine
    let moveIndex: Int   // Used to number moves correctly in PV

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Line number badge
            Text("\(line.id)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))

            // PV move sequence
            pvText
                .frame(maxWidth: .infinity, alignment: .leading)

            // Score
            Text(line.score.displayString)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(scoreColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentTransition(.numericText())
    }

    private var pvText: some View {
        let numbered = numberedPV
        return Text(numbered)
            .font(.system(.footnote, design: .monospaced))
            .lineLimit(2)
            .foregroundStyle(.primary)
    }

    /// PV moves with inline move numbers: "18. e4 e5 19. Nf3 Nc6 …"
    /// `moveIndex` = number of game half-moves already played.
    private var numberedPV: String {
        guard !line.pvSANs.isEmpty else { return "" }

        // Which chess move number does the NEXT half-move belong to?
        // Half-move 0 = start (White's move 1), half-move 1 = Black's move 1, etc.
        var halfMove = moveIndex   // 0-based: 0 = White turn, 1 = Black turn, 2 = White turn…
        var parts: [String] = []

        for san in line.pvSANs {
            let moveNum = halfMove / 2 + 1
            let isWhite = halfMove % 2 == 0
            if isWhite {
                parts.append("\(moveNum). \(san)")
            } else {
                // Only prepend "N…" if this is the very first token and Black moves first
                if parts.isEmpty {
                    parts.append("\(moveNum)… \(san)")
                } else {
                    parts.append(san)
                }
            }
            halfMove += 1
        }

        return parts.joined(separator: " ")
    }

    private var scoreColor: Color {
        switch line.score {
        case .mate(let n):         return n > 0 ? .green : .red
        case .centipawns(let cp):
            if cp > 50  { return .green }
            if cp < -50 { return .red   }
            return .primary
        }
    }
}

// MARK: - Preview

#Preview {
    let game = SavedGame(
        playerColorRaw: "white",
        outcomeRaw: "playerWins",
        skillLevel: 10,
        moveSANs: ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6", "O-O", "Be7"]
    )
    return NavigationStack {
        GameReviewView(game: game)
    }
    .modelContainer(for: SavedGame.self, inMemory: true)
}
