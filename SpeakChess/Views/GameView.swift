import SwiftUI
import SwiftData
import ChessKit
import OSLog

struct GameView: View {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SpeakChess",
        category: "GameView"
    )

    let playerColor: Piece.Color
    let skillLevel: Int
    /// Non-nil when resuming an existing in-progress game from the home screen.
    let resumeGame: SavedGame?

    @StateObject private var gm: GameManager
    @StateObject private var em = EngineManager()
    @StateObject private var sr = SpeechRecognitionService()
    @StateObject private var tts = SpeechSynthesisService()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var voiceModeEnabled = false
    @State private var voicePermissionDenied = false
    @State private var listeningPulse = false
    /// The SwiftData record for the current game; created on the first move (or reused when resuming).
    @State private var activeSavedGame: SavedGame?
    /// Last text spoken by TTS — replayed when the player says "repeat".
    @State private var lastSpokenText: String = ""
    /// The player's own move echo, stored until the bot replies so both are spoken together.
    @State private var pendingPlayerEcho: String = ""

    init(playerColor: Piece.Color, skillLevel: Int, resumeGame: SavedGame? = nil) {
        self.playerColor = playerColor
        self.skillLevel = skillLevel
        self.resumeGame = resumeGame
        self._gm = StateObject(wrappedValue: GameManager(playerColor: playerColor))
        self._activeSavedGame = State(initialValue: resumeGame)
    }

    var body: some View {
        VStack(spacing: 0) {
            opponentHeader
            board
            playerFooter
            statusBar
            if voiceModeEnabled {
                voiceTranscriptionBar
            }
            moveHistoryBar
            actionRow
        }
        .background(Color(.systemBackground))
        .navigationTitle("SpeakChess")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(gm.isWaitingForBot || em.isThinking)
        .task { await setupGame() }
        .onDisappear {
            Task {
                await em.stopEngine()
                sr.stopListening()
                tts.stopSpeaking()
                sr.releaseAudioSession()
            }
        }
        .onChange(of: gm.isWaitingForBot) { _, waiting in
            if waiting { requestBotMove() }
        }
        // After TTS finishes, restart listening if voice mode is on and it's player's turn.
        // The 1.0 s delay gives the speaker's audio enough time to decay so the mic
        // doesn't pick up the tail of the TTS output and feed it back into recognition.
        .onChange(of: tts.isSpeaking) { _, isSpeaking in
            if !isSpeaking && voiceModeEnabled && gm.isPlayerTurn {
                logger.debug("tts finished; scheduling mic restart")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard voiceModeEnabled, gm.isPlayerTurn, !tts.isSpeaking else { return }
                    sr.startListening()
                }
            }
        }
        // Process each final transcription from the speech recogniser
        .onChange(of: sr.finalTranscriptionCount) { _, _ in
            handleVoiceTranscription()
        }
        // Persist in-progress state and play sound after every move
        .onChange(of: gm.moveHistory.count) { _, _ in
            persistCurrentState()
            playSoundForLastMove()
        }
        // Finalize the saved record and play end sound when the game ends
        .onChange(of: gm.outcome) { _, outcome in
            if let rawOutcome = outcome.saveString {
                finalizeGame(rawOutcome: rawOutcome)
                SoundService.shared.playGameEnd()
            }
        }
        // Promotion overlay
        .overlay {
            if gm.pendingPromotion != nil {
                promotionOverlay
            }
        }
    }

    // MARK: - Subviews

    private var opponentHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(gm.playerColor.opposite == .white ? "♔" : "♚")
                    .font(.title2)
                Text("Stockfish")
                    .font(.headline)
                Text(difficultyLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if em.isThinking {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Pieces the player captured from the bot, plus advantage label if bot is losing
            capturedPiecesRow(
                count: gm.capturedByPlayer,
                pieceColor: gm.playerColor.opposite,
                advantage: gm.materialAdvantage > 0 ? gm.materialAdvantage : 0
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var board: some View {
        ChessBoardView(
            board: gm.board,
            playerColor: gm.playerColor,
            selectedSquare: gm.selectedSquare,
            legalMoveSquares: gm.legalMoveSquares,
            lastMove: gm.lastMove,
            onSquareTap: { gm.handleSquareTap($0) }
        )
        .padding(.horizontal, 6)
    }

    private var playerFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Pieces the bot captured from the player, plus advantage label if bot is winning
            capturedPiecesRow(
                count: gm.capturedByBot,
                pieceColor: gm.playerColor,
                advantage: gm.materialAdvantage < 0 ? -gm.materialAdvantage : 0
            )
            HStack(spacing: 8) {
                Text(gm.playerColor == .white ? "♔" : "♚")
                    .font(.title2)
                Text("You")
                    .font(.headline)
                Spacer()
                // Voice mode toggle
                if !gm.isGameOver {
                    Button {
                        toggleVoiceMode()
                    } label: {
                        Image(systemName: micIconName)
                            .font(.title3)
                            .foregroundStyle(micIconColor)
                            .symbolEffect(.pulse, isActive: sr.recognitionState == .listening)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(voiceModeEnabled ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                    }
                    .accessibilityLabel(voiceModeEnabled ? "Disable voice mode" : "Enable voice mode")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var micIconName: String {
        switch sr.recognitionState {
        case .listening: return "mic.fill"
        case .unavailable: return "mic.slash"
        case .idle:       return voiceModeEnabled ? "mic" : "mic.slash"
        }
    }

    private var micIconColor: Color {
        if voicePermissionDenied { return .red }
        if sr.recognitionState == .listening { return .accentColor }
        return voiceModeEnabled ? .primary : .secondary
    }

    /// Renders a row of captured piece symbols plus an optional material advantage label.
    @ViewBuilder
    private func capturedPiecesRow(
        count: GameManager.CapturedPieceCount,
        pieceColor: Piece.Color,
        advantage: Int
    ) -> some View {
        let symbols = count.symbols(color: pieceColor)
        if !symbols.isEmpty || advantage > 0 {
            HStack(spacing: 1) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 13))
                }
                if advantage > 0 {
                    Text("+\(advantage)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 3)
                }
                Spacer()
            }
            .padding(.horizontal, 2)
        }
    }

    private var voiceTranscriptionBar: some View {
        HStack(spacing: 8) {
            Image(systemName: sr.recognitionState == .listening ? "waveform" : "waveform.slash")
                .font(.caption)
                .foregroundStyle(sr.recognitionState == .listening ? Color.accentColor : .secondary)
                .symbolEffect(.pulse, isActive: sr.recognitionState == .listening)

            Group {
                if voicePermissionDenied {
                    Text("Microphone or speech access denied")
                        .foregroundStyle(.red)
                } else if sr.recognitionState == .listening {
                    Text(sr.partialTranscription.isEmpty ? "Listening…" : sr.partialTranscription)
                        .foregroundStyle(sr.partialTranscription.isEmpty ? .secondary : .primary)
                } else if sr.recognitionState == .unavailable {
                    Text("Speech recognition unavailable")
                        .foregroundStyle(.secondary)
                } else {
                    Text(gm.isPlayerTurn ? "Say your move" : "Voice mode on")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
    }

    private var statusBar: some View {
        Text(gm.statusText)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(statusColor)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .background(statusColor.opacity(0.08))
    }

    private var statusColor: Color {
        switch gm.outcome {
        case .playerWins:  return .green
        case .botWins:     return .red
        case .draw(_):     return .orange
        case .ongoing:
            if case .check = gm.board.state { return .orange }
            return .primary
        }
    }

    private var moveHistoryBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if gm.moveHistory.isEmpty {
                        Text("No moves yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(movePairs) { pair in
                            HStack(spacing: 3) {
                                Text("\(pair.number).")
                                    .foregroundStyle(.secondary)
                                moveText(pair.white, isLast: pair.isLastWhite)
                                if let black = pair.black {
                                    moveText(black, isLast: pair.isLastBlack)
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
            .onChange(of: gm.moveHistory.count) { _, _ in
                if let last = movePairs.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .trailing) }
                }
            }
        }
        .frame(height: 44)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func moveText(_ san: String, isLast: Bool) -> some View {
        Text(san)
            .fontWeight(isLast ? .bold : .regular)
            .foregroundStyle(isLast ? Color.accentColor : Color.primary)
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            if gm.isGameOver {
                Button("New Game") { dismiss() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(role: .destructive) {
                    gm.resign()
                } label: {
                    Label("Resign", systemImage: "flag")
                }
                .buttonStyle(.bordered)
                .disabled(gm.isWaitingForBot || em.isThinking)

                Button {
                    gm.undoLastTwoMoves()
                    sr.stopListening()
                    if voiceModeEnabled && gm.isPlayerTurn {
                        sr.startListening()
                    }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(gm.moveHistory.count < 2 || gm.isWaitingForBot || em.isThinking)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    // MARK: - Promotion overlay

    private var promotionOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Promote pawn to…")
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 24) {
                    ForEach([Piece.Kind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                        Button {
                            gm.completePlayerPromotion(to: kind)
                        } label: {
                            VStack(spacing: 4) {
                                Text(Piece(kind, color: gm.playerColor, square: .a1).unicodeSymbol)
                                    .font(.system(size: 52))
                                Text(kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
            .padding(32)
            .background(Color(.systemBackground).opacity(0.15))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Engine interaction

    private func setupGame() async {
        em.skillLevel = skillLevel
        await em.startEngine()

        if let resume = resumeGame {
            gm.restoreGame(moveSANs: resume.moveSANs, as: playerColor)
            // If the saved position needs a bot reply, trigger it now that the engine is ready
            if !gm.isGameOver && gm.board.position.sideToMove != playerColor {
                requestBotMove()
            }
        } else {
            gm.startNewGame(as: playerColor)
            if playerColor == .black {
                requestBotMove()
            }
        }
    }

    private func requestBotMove() {
        guard !em.isThinking else { return }
        logger.debug("requestBotMove start")
        Task {
            let fen = gm.currentFEN
            if let lan = await em.requestBestMove(fen: fen) {
                logger.debug("bot move received: \(lan, privacy: .public)")
                gm.applyBotMove(lan: lan)
                if voiceModeEnabled, let move = gm.lastMove {
                    let botNarration = MoveNarrator.narrate(move: move)
                    // Prepend the player's move echo (if any) so both are spoken as one utterance.
                    // This avoids the echo being cut off mid-sentence when the bot responds quickly.
                    let echo = pendingPlayerEcho
                    pendingPlayerEcho = ""
                    let fullSpeech = echo.isEmpty ? botNarration : "\(echo). \(botNarration)"
                    logger.debug("speaking bot narration")
                    speak(fullSpeech)
                } else if voiceModeEnabled {
                    pendingPlayerEcho = ""
                    sr.startListening()
                }
            } else {
                logger.error("bot move unavailable after engine restart retry")
                gm.isWaitingForBot = false
                pendingPlayerEcho = ""
                if voiceModeEnabled {
                    speak("Stockfish stopped responding. Starting a new game is recommended.")
                }
                if voiceModeEnabled && gm.isPlayerTurn {
                    sr.startListening()
                }
            }
        }
    }

    // MARK: - Voice interaction

    private func toggleVoiceMode() {
        if voiceModeEnabled {
            voiceModeEnabled = false
            sr.stopListening()
            sr.releaseAudioSession()
        } else {
            Task {
                let granted = await sr.requestPermissions()
                if granted {
                    voicePermissionDenied = false
                    voiceModeEnabled = true
                    if gm.isPlayerTurn {
                        sr.startListening()
                    }
                } else {
                    voicePermissionDenied = true
                }
            }
        }
    }

    private func handleVoiceTranscription() {
        let text = sr.lastFinalText
        guard !text.isEmpty else { return }
        logger.debug("handleVoiceTranscription text: \(text, privacy: .public)")

        let normalized = VoiceMoveParser.normalize(text)

        // If every word was noise (or the mic picked up TTS output that filtered to
        // nothing), silently restart the mic instead of saying "illegal move".
        guard !normalized.isEmpty else {
            if voiceModeEnabled && gm.isPlayerTurn { sr.startListening() }
            return
        }

        let words = normalized.split(separator: " ").map(String.init)

        // --- Special commands (work regardless of whose turn it is) ---

        if words.contains("undo") {
            handleUndoCommand()
            return
        }

        if words.contains("repeat") || words.contains("again") {
            handleRepeatCommand()
            return
        }

        if let square = VoiceMoveParser.parseSquareQuery(normalized) {
            handleSquareQueryCommand(square: square)
            return
        }

        // --- Chess move (only on the player's turn) ---

        guard gm.isPlayerTurn else {
            if voiceModeEnabled { sr.startListening() }
            return
        }

        let parsed = VoiceMoveParser.parse(
            transcription: text,
            board: gm.board,
            playerColor: gm.playerColor
        )

        if let parsed,
           let move = gm.applyVoiceMove(start: parsed.start, end: parsed.end,
                                        promotionKind: parsed.promotionKind) {
            logger.debug("voice move accepted")
            // Build the echo from the raw transcription + any check/checkmate annotation
            let echo = buildPlayerEcho(transcription: text, move: move)
            if gm.isGameOver {
                // No bot reply — speak the echo immediately (e.g. player checkmated the bot)
                speak(echo)
            } else {
                // Store for concatenation with the bot's upcoming narration
                pendingPlayerEcho = echo
            }
        } else {
            if voiceModeEnabled {
                logger.debug("voice move rejected")
                // Echo what the user said with "illegal move" appended so the phrase
                // is stored in lastSpokenText and "repeat" replays the full rejection.
                let rejection = "\(text.trimmingCharacters(in: .whitespaces)). Illegal move."
                speak(rejection)
            }
        }
    }

    // MARK: - Special voice commands

    private func handleUndoCommand() {
        guard !em.isThinking && !gm.isWaitingForBot else {
            speak("Can't undo right now.")
            return
        }
        guard gm.moveHistory.count >= 2 else {
            speak("Nothing to undo.")
            return
        }
        pendingPlayerEcho = ""
        gm.undoLastTwoMoves()
        sr.stopListening()
        speak("Undone.")
        // Listening restarts automatically when TTS finishes (onChange of tts.isSpeaking)
    }

    private func handleRepeatCommand() {
        guard !lastSpokenText.isEmpty else {
            sr.startListening()
            return
        }
        speak(lastSpokenText)
        // Listening restarts when TTS finishes
    }

    private func handleSquareQueryCommand(square: Square) {
        if let piece = gm.board.position.piece(at: square) {
            let colorName = piece.color == .white ? "white" : "black"
            speak("The \(colorName) \(piece.kind.spokenName).")
        } else {
            speak("No piece on \(VoiceMoveParser.spokenSquare(square)).")
        }
    }

    /// Builds the readback phrase for the player's own move.
    /// Uses the raw transcription so the app echoes exactly what was said,
    /// then appends a check or checkmate annotation if the move delivers one.
    private func buildPlayerEcho(transcription: String, move: Move) -> String {
        let base = transcription.trimmingCharacters(in: .whitespaces)
        switch move.checkState {
        case .checkmate: return "\(base). Checkmate"
        case .check:     return "\(base). Check"
        case .stalemate: return "\(base). Stalemate"
        case .none:      return base
        }
    }

    // MARK: - TTS wrapper

    /// Speaks `text` aloud and records it as the most-recent utterance for "repeat".
    /// Always stops the microphone first — otherwise TTS re-configuring the shared
    /// AVAudioSession while the mic's audio engine is still streaming causes a
    /// Core Audio HAL crash ("iOSSimulatorAudioDevice: reconfig pending" on the simulator,
    /// and a hard crash on some real devices).
    private func speak(_ text: String) {
        logger.debug("speak text: \(text, privacy: .public)")
        sr.stopListening()
        lastSpokenText = text
        tts.speak(text)
    }

    // MARK: - Sound

    private func playSoundForLastMove() {
        // System sounds on the simulator are fighting with the voice pipeline's shared
        // audio session and are the source of the loud chirp right before termination.
        // Keep them for normal tap play, but suppress them while voice mode is active.
        guard !voiceModeEnabled else { return }
        guard let move = gm.lastMove else { return }
        if case .capture = move.result {
            SoundService.shared.playCapture()
        } else {
            SoundService.shared.playMove()
        }
        if move.checkState == .check {
            SoundService.shared.playCheck()
        }
    }

    // MARK: - Persistence

    /// Called on every move; inserts a new SwiftData record on the first move, then updates it.
    private func persistCurrentState() {
        let sans = gm.moveHistory.map(\.san)
        guard !sans.isEmpty else { return }

        if let saved = activeSavedGame {
            saved.moveSANs = sans
        } else {
            let saved = SavedGame(
                playerColorRaw: playerColor == .white ? "white" : "black",
                outcomeRaw: "ongoing",
                skillLevel: skillLevel,
                moveSANs: sans
            )
            modelContext.insert(saved)
            activeSavedGame = saved
        }
    }

    /// Called when the game ends; updates the outcome on the existing record (or creates one
    /// in the rare case the game ended before the first move onChange fired).
    private func finalizeGame(rawOutcome: String) {
        let sans = gm.moveHistory.map(\.san)
        guard !sans.isEmpty else { return }

        if let saved = activeSavedGame {
            saved.outcomeRaw = rawOutcome
            saved.moveSANs = sans
        } else {
            let saved = SavedGame(
                playerColorRaw: playerColor == .white ? "white" : "black",
                outcomeRaw: rawOutcome,
                skillLevel: skillLevel,
                moveSANs: sans
            )
            modelContext.insert(saved)
        }
    }

    // MARK: - Move history helpers

    private struct MovePair: Identifiable {
        let id: Int
        let number: Int
        let white: String
        let black: String?
        let isLastWhite: Bool
        let isLastBlack: Bool
    }

    private var movePairs: [MovePair] {
        let history = gm.moveHistory
        guard !history.isEmpty else { return [] }

        var pairs: [MovePair] = []
        var i = 0
        var moveNum = 1

        while i < history.count {
            let whiteMove  = history[i].san
            let blackMove  = (i + 1 < history.count) ? history[i + 1].san : nil
            let isLastWhite = (i == history.count - 1)
            let isLastBlack = (i + 1 == history.count - 1)

            pairs.append(MovePair(
                id: moveNum,
                number: moveNum,
                white: whiteMove,
                black: blackMove,
                isLastWhite: isLastWhite,
                isLastBlack: isLastBlack
            ))

            i += 2
            moveNum += 1
        }
        return pairs
    }
}

// MARK: - Difficulty label

private extension GameView {
    var difficultyLabel: String {
        switch skillLevel {
        case 0...3:   return "Beginner"
        case 4...7:   return "Intermediate"
        case 8...12:  return "Advanced"
        case 13...17: return "Expert"
        default:      return "Master"
        }
    }
}

// MARK: - Piece.Kind display name

private extension Piece.Kind {
    var displayName: String {
        switch self {
        case .queen:  "Queen"
        case .rook:   "Rook"
        case .bishop: "Bishop"
        case .knight: "Knight"
        case .king:   "King"
        case .pawn:   "Pawn"
        }
    }
}
