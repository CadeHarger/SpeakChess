import Testing
import ChessKit
@testable import SpeakChess

// MARK: - VoiceMoveParser: Normalization

@Suite("VoiceMoveParser – normalize")
struct NormalizeTests {

    @Test("Noise words are stripped")
    func noiseWordsRemoved() {
        let result = VoiceMoveParser.normalize("please move the pawn")
        #expect(!result.contains("please"))
        #expect(!result.contains("the"))
        #expect(!result.contains("move"))
        #expect(result == "pawn")
    }

    @Test("Rank homophones expand correctly")
    func rankHomophones() {
        #expect(VoiceMoveParser.normalize("won") == "one")
        #expect(VoiceMoveParser.normalize("too") == "two")
        #expect(VoiceMoveParser.normalize("tow") == "two")
        #expect(VoiceMoveParser.normalize("for") == "four")
        #expect(VoiceMoveParser.normalize("fore") == "four")
        #expect(VoiceMoveParser.normalize("ate") == "eight")
        #expect(VoiceMoveParser.normalize("aight") == "eight")
        #expect(VoiceMoveParser.normalize("free") == "three")
    }

    @Test("File homophones expand correctly")
    func fileHomophones() {
        #expect(VoiceMoveParser.normalize("see") == "c")
        #expect(VoiceMoveParser.normalize("sea") == "c")
        #expect(VoiceMoveParser.normalize("bee") == "b")
        #expect(VoiceMoveParser.normalize("dee") == "d")
        #expect(VoiceMoveParser.normalize("ef") == "f")
        #expect(VoiceMoveParser.normalize("eff") == "f")
        #expect(VoiceMoveParser.normalize("gee") == "g")
    }

    @Test("Piece homophones expand correctly")
    func pieceHomophones() {
        #expect(VoiceMoveParser.normalize("night") == "knight")
        #expect(VoiceMoveParser.normalize("nite") == "knight")
        #expect(VoiceMoveParser.normalize("rock") == "rook")
        #expect(VoiceMoveParser.normalize("pawns") == "pawn")
    }

    @Test("Castling synonyms are canonicalized")
    func castlingSynonyms() {
        #expect(VoiceMoveParser.normalize("castles") == "castle")
        #expect(VoiceMoveParser.normalize("castling") == "castle")
    }

    @Test("Capture synonyms are canonicalized")
    func captureSynonyms() {
        #expect(VoiceMoveParser.normalize("capture") == "takes")
        #expect(VoiceMoveParser.normalize("captures") == "takes")
        #expect(VoiceMoveParser.normalize("eats") == "takes")
    }

    @Test("'to' as preposition is preserved — not treated as rank '2'")
    func prepositionToNotMapToTwo() {
        // "to" should NOT be canonicalized to "two" (the rank digit).
        // This prevents "knight to f three" from spuriously matching
        // forms that reference rank 2 (e.g., "knight d two f three").
        let result = VoiceMoveParser.normalize("knight to f three")
        #expect(!result.contains("two"),
                "\"to\" should not become \"two\" — it's a preposition, not the rank digit")
    }

    @Test("Empty and whitespace input returns empty string")
    func emptyInput() {
        #expect(VoiceMoveParser.normalize("") == "")
        #expect(VoiceMoveParser.normalize("   ") == "")
        #expect(VoiceMoveParser.normalize("um uh er") == "")
    }

    @Test("Hyphenated words are split into separate tokens before processing")
    func hyphenatedWords() {
        // Hyphens are replaced with spaces, so "king-side" → two tokens "king" + "side"
        let result = VoiceMoveParser.normalize("king-side")
        #expect(result == "king side")
    }
}

// MARK: - VoiceMoveParser: spokenSquare / spokenRank

@Suite("VoiceMoveParser – spoken square helpers")
struct SpokenSquareTests {

    @Test("spokenRank returns correct words")
    func spokenRanks() {
        #expect(VoiceMoveParser.spokenRank(1) == "one")
        #expect(VoiceMoveParser.spokenRank(2) == "two")
        #expect(VoiceMoveParser.spokenRank(3) == "three")
        #expect(VoiceMoveParser.spokenRank(4) == "four")
        #expect(VoiceMoveParser.spokenRank(5) == "five")
        #expect(VoiceMoveParser.spokenRank(6) == "six")
        #expect(VoiceMoveParser.spokenRank(7) == "seven")
        #expect(VoiceMoveParser.spokenRank(8) == "eight")
    }

    @Test("spokenSquare formats file and rank")
    func spokenSquares() {
        #expect(VoiceMoveParser.spokenSquare(Square("e4")) == "e four")
        #expect(VoiceMoveParser.spokenSquare(Square("a1")) == "a one")
        #expect(VoiceMoveParser.spokenSquare(Square("h8")) == "h eight")
        #expect(VoiceMoveParser.spokenSquare(Square("d2")) == "d two")
        #expect(VoiceMoveParser.spokenSquare(Square("g7")) == "g seven")
    }
}

// MARK: - VoiceMoveParser: parse (starting position)

@Suite("VoiceMoveParser – parse from starting position")
struct ParseFromStartTests {

    // Board at the initial position, White to move.
    private var board: Board { Board() }

    @Test("Pawn push 'e four' is recognized")
    func pawnPushE4() throws {
        let result = VoiceMoveParser.parse(
            transcription: "e four",
            board: board,
            playerColor: .white
        )
        let move = try #require(result, "Should parse 'e four' as a pawn move")
        #expect(move.start == Square("e2"))
        #expect(move.end   == Square("e4"))
        #expect(move.promotionKind == nil)
    }

    @Test("'pawn e four' is recognized")
    func pawnE4WithPawnPrefix() throws {
        let result = VoiceMoveParser.parse(
            transcription: "pawn e four",
            board: board,
            playerColor: .white
        )
        let move = try #require(result)
        #expect(move.end == Square("e4"))
    }

    @Test("'knight f three' moves g1 knight")
    func knightToF3() throws {
        let result = VoiceMoveParser.parse(
            transcription: "knight f three",
            board: board,
            playerColor: .white
        )
        let move = try #require(result)
        #expect(move.start == Square("g1"))
        #expect(move.end   == Square("f3"))
    }

    @Test("'night f three' (homophone) moves g1 knight")
    func knightHomophone() throws {
        let result = VoiceMoveParser.parse(
            transcription: "night f three",
            board: board,
            playerColor: .white
        )
        let move = try #require(result)
        #expect(move.end == Square("f3"))
    }

    @Test("'knight to f three' moves g1 knight (preposition 'to' must not corrupt rank matching)")
    func knightToF3WithPreposition() throws {
        // This test also validates that "to" is not misinterpreted as rank "two".
        let result = VoiceMoveParser.parse(
            transcription: "knight to f three",
            board: board,
            playerColor: .white
        )
        let move = try #require(result, "Should parse 'knight to f three' as Ng1-f3")
        #expect(move.start == Square("g1"))
        #expect(move.end   == Square("f3"))
    }

    @Test("Garbled input returns nil")
    func garbledInput() {
        let result = VoiceMoveParser.parse(
            transcription: "banana pizza frog",
            board: board,
            playerColor: .white
        )
        #expect(result == nil)
    }

    @Test("Empty transcription returns nil")
    func emptyTranscription() {
        let result = VoiceMoveParser.parse(
            transcription: "",
            board: board,
            playerColor: .white
        )
        #expect(result == nil)
    }

    @Test("Noise-only transcription returns nil")
    func noisyTranscription() {
        let result = VoiceMoveParser.parse(
            transcription: "um uh please move",
            board: board,
            playerColor: .white
        )
        #expect(result == nil)
    }

    @Test("'knight c three' moves b1 knight")
    func knightToC3() throws {
        let result = VoiceMoveParser.parse(
            transcription: "knight c three",
            board: board,
            playerColor: .white
        )
        let move = try #require(result)
        #expect(move.start == Square("b1"))
        #expect(move.end   == Square("c3"))
    }

    @Test("Black pawn move is parsed when it is Black's turn")
    func blackPawnD5() throws {
        // Advance board: 1. e4 (White pawn to e4 to make it Black's turn)
        var b = Board()
        _ = b.move(pieceAt: Square("e2"), to: Square("e4"))

        let result = VoiceMoveParser.parse(
            transcription: "d five",
            board: b,
            playerColor: .black
        )
        let move = try #require(result)
        #expect(move.start == Square("d7"))
        #expect(move.end   == Square("d5"))
    }
}

// MARK: - VoiceMoveParser: castling

@Suite("VoiceMoveParser – castling")
struct CastlingParseTests {

    /// Returns a board prepared for White to castle kingside (f1, g1 clear).
    private func boardReadyForKingsideCastle() -> Board {
        Board(position: Position(
            fen: "rnbqkbnr/pppppppp/8/8/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq e3 0 1"
        )!)
    }

    @Test("'castle kingside' is recognized")
    func castleKingside() throws {
        // FEN with White able to castle kingside (f1, g1 clear)
        var b = Board(position: Position(
            fen: "rnbqk2r/pppp1ppp/4pn2/8/2B1P3/8/PPPP1PPP/RNBQK2R w KQkq - 0 4"
        )!)
        let result = VoiceMoveParser.parse(
            transcription: "castle kingside",
            board: b,
            playerColor: .white
        )
        let move = try #require(result, "Should recognize 'castle kingside'")
        #expect(move.start == Square("e1"))
        #expect(move.end   == Square("g1"))
    }

    @Test("'o o' is recognized as castling")
    func ooNotation() throws {
        var b = Board(position: Position(
            fen: "rnbqk2r/pppp1ppp/4pn2/8/2B1P3/8/PPPP1PPP/RNBQK2R w KQkq - 0 4"
        )!)
        let result = VoiceMoveParser.parse(
            transcription: "o o",
            board: b,
            playerColor: .white
        )
        let move = try #require(result, "Should recognize 'o o' as castling")
        #expect(move.end == Square("g1"))
    }
}

// MARK: - MoveNarrator

@Suite("MoveNarrator")
struct MoveNarratorTests {

    @Test("Pawn push is narrated as destination square")
    func pawnPush() throws {
        var b = Board()
        let pawnMove = b.move(pieceAt: Square("e2"), to: Square("e4"))
        let move = try #require(pawnMove)
        let text = MoveNarrator.narrate(move: move)
        #expect(text == "E four.")
    }

    @Test("Knight move is narrated as 'Knight to <square>'")
    func knightMove() throws {
        var b = Board()
        _ = b.move(pieceAt: Square("e2"), to: Square("e4"))
        _ = b.move(pieceAt: Square("e7"), to: Square("e5"))
        let knightMove = b.move(pieceAt: Square("g1"), to: Square("f3"))
        let move = try #require(knightMove)
        let text = MoveNarrator.narrate(move: move)
        #expect(text == "Knight to f three.")
    }

    @Test("Pawn capture is narrated as '<file> takes <square>'")
    func pawnCapture() throws {
        // 1. e4 e5 2. d4 exd4 — Black pawn on e5 captures White pawn on d4
        var b = Board()
        _ = b.move(pieceAt: Square("e2"), to: Square("e4"))
        _ = b.move(pieceAt: Square("e7"), to: Square("e5"))
        _ = b.move(pieceAt: Square("d2"), to: Square("d4"))
        let captureMove = b.move(pieceAt: Square("e5"), to: Square("d4"))
        let move = try #require(captureMove)
        let text = MoveNarrator.narrate(move: move)
        #expect(text == "E takes d four.")
    }

    @Test("Kingside castle is narrated as 'Castle kingside'")
    func kingsideCastle() throws {
        var b = Board(position: Position(
            fen: "rnbqk2r/pppp1ppp/4pn2/8/2B1P3/8/PPPP1PPP/RNBQK2R w KQkq - 0 4"
        )!)
        let castleMove = b.move(pieceAt: Square("e1"), to: Square("g1"))
        let move = try #require(castleMove)
        let text = MoveNarrator.narrate(move: move)
        #expect(text == "Castle kingside.")
    }
}

// MARK: - ReviewManager

@Suite("ReviewManager – navigation")
@MainActor
struct ReviewManagerTests {

    private let italianSANs = ["e4", "e5", "Nf3", "Nc6", "Bc4"]

    @Test("Starts at index 0 (before first move)")
    func startsAtZero() {
        let rm = ReviewManager(moveSANs: italianSANs)
        #expect(rm.currentMoveIndex == 0)
        #expect(rm.isAtStart)
        #expect(!rm.isAtEnd)
    }

    @Test("stepForward advances index by 1")
    func stepForward() {
        let rm = ReviewManager(moveSANs: italianSANs)
        rm.stepForward()
        #expect(rm.currentMoveIndex == 1)
    }

    @Test("stepBack does nothing at start")
    func stepBackAtStart() {
        let rm = ReviewManager(moveSANs: italianSANs)
        rm.stepBack()
        #expect(rm.currentMoveIndex == 0)
        #expect(rm.isAtStart)
    }

    @Test("jumpToEnd goes to last move index")
    func jumpToEnd() {
        let rm = ReviewManager(moveSANs: italianSANs)
        rm.jumpToEnd()
        #expect(rm.currentMoveIndex == italianSANs.count)
        #expect(rm.isAtEnd)
    }

    @Test("stepForward does nothing at end")
    func stepForwardAtEnd() {
        let rm = ReviewManager(moveSANs: italianSANs)
        rm.jumpToEnd()
        rm.stepForward()
        #expect(rm.currentMoveIndex == italianSANs.count)
    }

    @Test("jumpToStart resets to index 0")
    func jumpToStart() {
        let rm = ReviewManager(moveSANs: italianSANs)
        rm.jumpToEnd()
        rm.jumpToStart()
        #expect(rm.currentMoveIndex == 0)
        #expect(rm.isAtStart)
    }

    @Test("stepBack from end decrements index")
    func stepBackFromEnd() {
        let rm = ReviewManager(moveSANs: italianSANs)
        rm.jumpToEnd()
        rm.stepBack()
        #expect(rm.currentMoveIndex == italianSANs.count - 1)
    }

    @Test("progressFraction is 0 at start and 1 at end")
    func progressFraction() {
        let rm = ReviewManager(moveSANs: italianSANs)
        #expect(rm.progressFraction == 0.0)
        rm.jumpToEnd()
        #expect(rm.progressFraction == 1.0)
    }

    @Test("progressFraction is 0 for empty game")
    func progressFractionEmpty() {
        let rm = ReviewManager(moveSANs: [])
        #expect(rm.progressFraction == 0.0)
    }

    @Test("Board reflects position after one move")
    func boardAfterOneMove() {
        let rm = ReviewManager(moveSANs: italianSANs)
        rm.stepForward()
        // After 1. e4, White pawn should be on e4, not e2
        let pos = rm.replayBoard.position
        #expect(pos.piece(at: Square("e4"))?.kind == .pawn)
        #expect(pos.piece(at: Square("e2")) == nil)
    }

    @Test("Board returns to start position at index 0")
    func boardAtStart() {
        let rm = ReviewManager(moveSANs: italianSANs)
        rm.jumpToEnd()
        rm.jumpToStart()
        let pos = rm.replayBoard.position
        // Starting position: pawns on rank 2 for White
        #expect(pos.piece(at: Square("e2"))?.kind == .pawn)
        #expect(pos.piece(at: Square("e4")) == nil)
    }

    @Test("lastAppliedMove is nil at start and non-nil after first step")
    func lastAppliedMove() {
        let rm = ReviewManager(moveSANs: italianSANs)
        #expect(rm.lastAppliedMove == nil)
        rm.stepForward()
        #expect(rm.lastAppliedMove != nil)
    }

    @Test("Round-trip forward then backward returns same board state")
    func roundTrip() {
        let rm = ReviewManager(moveSANs: italianSANs)
        rm.jumpToEnd()
        let fenAtEnd = rm.replayBoard.position.fen
        rm.stepBack()
        rm.stepForward()
        #expect(rm.replayBoard.position.fen == fenAtEnd)
    }

    @Test("Empty move list: isAtStart and isAtEnd are both true")
    func emptyMoveList() {
        let rm = ReviewManager(moveSANs: [])
        #expect(rm.isAtStart)
        #expect(rm.isAtEnd)
        #expect(rm.totalMoves == 0)
    }
}

// MARK: - GameOutcome

@Suite("GameOutcome – saveString")
struct GameOutcomeTests {

    @Test(".ongoing produces nil")
    func ongoingIsNil() {
        #expect(GameOutcome.ongoing.saveString == nil)
    }

    @Test(".playerWins produces correct string")
    func playerWins() {
        #expect(GameOutcome.playerWins.saveString == "playerWins")
    }

    @Test(".botWins produces correct string")
    func botWins() {
        #expect(GameOutcome.botWins.saveString == "botWins")
    }

    @Test(".draw encodes the reason")
    func drawEncoding() {
        #expect(GameOutcome.draw("stalemate").saveString == "draw:stalemate")
        #expect(GameOutcome.draw("fifty-move rule").saveString == "draw:fifty-move rule")
    }
}

// MARK: - SavedGame display properties

@Suite("SavedGame – display properties")
struct SavedGameTests {

    @Test("outcomeDisplay for playerWins")
    func outcomeDisplayWin() {
        let g = SavedGame(playerColorRaw: "white", outcomeRaw: "playerWins",
                          skillLevel: 10, moveSANs: [])
        #expect(g.outcomeDisplay == "You won")
    }

    @Test("outcomeDisplay for botWins")
    func outcomeDisplayLoss() {
        let g = SavedGame(playerColorRaw: "white", outcomeRaw: "botWins",
                          skillLevel: 10, moveSANs: [])
        #expect(g.outcomeDisplay == "Stockfish won")
    }

    @Test("outcomeDisplay for draw extracts reason")
    func outcomeDisplayDraw() {
        let g = SavedGame(playerColorRaw: "white", outcomeRaw: "draw:stalemate",
                          skillLevel: 10, moveSANs: [])
        #expect(g.outcomeDisplay == "Draw — stalemate")
    }

    @Test("outcomeSymbol for playerWins is trophy")
    func outcomeSymbolWin() {
        let g = SavedGame(playerColorRaw: "white", outcomeRaw: "playerWins",
                          skillLevel: 10, moveSANs: [])
        #expect(g.outcomeSymbol == "trophy.fill")
    }

    @Test("outcomeSymbol for botWins is cpu")
    func outcomeSymbolLoss() {
        let g = SavedGame(playerColorRaw: "black", outcomeRaw: "botWins",
                          skillLevel: 5, moveSANs: [])
        #expect(g.outcomeSymbol == "cpu")
    }

    @Test("outcomeSymbol for draw is equal circle")
    func outcomeSymbolDraw() {
        let g = SavedGame(playerColorRaw: "white", outcomeRaw: "draw:repetition",
                          skillLevel: 8, moveSANs: [])
        #expect(g.outcomeSymbol == "equal.circle.fill")
    }

    @Test("playerColorDisplay for white")
    func playerColorDisplayWhite() {
        let g = SavedGame(playerColorRaw: "white", outcomeRaw: "playerWins",
                          skillLevel: 10, moveSANs: [])
        #expect(g.playerColorDisplay == "White")
        #expect(g.isPlayerWhite)
    }

    @Test("playerColorDisplay for black")
    func playerColorDisplayBlack() {
        let g = SavedGame(playerColorRaw: "black", outcomeRaw: "botWins",
                          skillLevel: 10, moveSANs: [])
        #expect(g.playerColorDisplay == "Black")
        #expect(!g.isPlayerWhite)
    }
}

// MARK: - SavedGame.isOngoing (Phase 3 addition)

@Suite("SavedGame – isOngoing")
struct SavedGameOngoingTests {

    @Test("isOngoing is true only for 'ongoing' outcomeRaw")
    func isOngoingTrue() {
        let g = SavedGame(playerColorRaw: "white", outcomeRaw: "ongoing",
                          skillLevel: 10, moveSANs: ["e4", "e5"])
        #expect(g.isOngoing)
    }

    @Test("isOngoing is false for completed outcomes")
    func isOngoingFalse() {
        for raw in ["playerWins", "botWins", "draw:stalemate"] {
            let g = SavedGame(playerColorRaw: "white", outcomeRaw: raw,
                              skillLevel: 10, moveSANs: [])
            #expect(!g.isOngoing, "Expected isOngoing == false for outcomeRaw='\(raw)'")
        }
    }

    @Test("outcomeDisplay for ongoing is 'In Progress'")
    func outcomeDisplayOngoing() {
        let g = SavedGame(playerColorRaw: "black", outcomeRaw: "ongoing",
                          skillLevel: 5, moveSANs: ["d4"])
        #expect(g.outcomeDisplay == "In Progress")
    }

    @Test("outcomeSymbol for ongoing is 'clock'")
    func outcomeSymbolOngoing() {
        let g = SavedGame(playerColorRaw: "white", outcomeRaw: "ongoing",
                          skillLevel: 10, moveSANs: [])
        #expect(g.outcomeSymbol == "clock")
    }
}

// MARK: - GameManager: restoreGame

@Suite("GameManager – restoreGame")
@MainActor
struct RestoreGameTests {

    @Test("Restoring empty SAN list yields starting position")
    func restoreEmpty() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: [], as: .white)
        #expect(gm.moveHistory.isEmpty)
        #expect(gm.lastMove == nil)
        #expect(gm.outcome == .ongoing)
        // White pawn on e2 in starting position
        #expect(gm.board.position.piece(at: Square("e2"))?.kind == .pawn)
    }

    @Test("Restoring two moves reproduces correct board state")
    func restoreTwoMoves() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["e4", "e5"], as: .white)
        #expect(gm.moveHistory.count == 2)
        #expect(gm.board.position.piece(at: Square("e4"))?.kind == .pawn)
        #expect(gm.board.position.piece(at: Square("e5"))?.kind == .pawn)
        #expect(gm.board.position.piece(at: Square("e2")) == nil)
        #expect(gm.board.position.piece(at: Square("e7")) == nil)
    }

    @Test("Restoring an Italian opening reproduces the correct FEN")
    func restoreItalian() {
        let gm = GameManager(playerColor: .white)
        let sans = ["e4", "e5", "Nf3", "Nc6", "Bc4"]
        gm.restoreGame(moveSANs: sans, as: .white)
        #expect(gm.moveHistory.count == 5)
        // Bishop should be on c4
        #expect(gm.board.position.piece(at: Square("c4"))?.kind == .bishop)
        // Knight should have moved from g1 to f3
        #expect(gm.board.position.piece(at: Square("f3"))?.kind == .knight)
        #expect(gm.board.position.piece(at: Square("g1")) == nil)
    }

    @Test("Restored game is not waiting for bot (caller handles that)")
    func restoreDoesNotSetWaitingForBot() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["e4"], as: .white)
        // After restoring a single move it's Black's turn but the manager
        // should NOT set isWaitingForBot — the GameView caller does that
        // after the engine is started.
        #expect(!gm.isWaitingForBot)
    }

    @Test("Restoring as Black player sets correct playerColor")
    func restoreAsBlack() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["d4", "d5"], as: .black)
        #expect(gm.playerColor == .black)
    }
}

// MARK: - GameManager: undoLastTwoMoves

@Suite("GameManager – undoLastTwoMoves")
@MainActor
struct UndoTests {

    @Test("Undo with fewer than 2 moves is a no-op")
    func undoWithOneMoveIsNoOp() {
        let gm = GameManager(playerColor: .white)
        gm.startNewGame(as: .white)
        _ = gm.applyVoiceMove(start: Square("e2"), end: Square("e4"), promotionKind: nil)
        let historyBefore = gm.moveHistory.count
        gm.undoLastTwoMoves()
        #expect(gm.moveHistory.count == historyBefore, "Should not undo with only 1 move")
    }

    @Test("Undo with zero moves is a no-op")
    func undoWithZeroMovesIsNoOp() {
        let gm = GameManager(playerColor: .white)
        gm.startNewGame(as: .white)
        gm.undoLastTwoMoves()
        #expect(gm.moveHistory.isEmpty)
    }

    @Test("Undo removes exactly two half-moves")
    func undoRemovesTwoHalfMoves() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["e4", "e5", "Nf3", "Nc6"], as: .white)
        #expect(gm.moveHistory.count == 4)
        gm.undoLastTwoMoves()
        #expect(gm.moveHistory.count == 2)
    }

    @Test("Board returns to state before the undone moves")
    func undoRestoresBoard() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["e4", "e5"], as: .white)
        let fenAfterTwo = gm.board.position.fen
        gm.restoreGame(moveSANs: ["e4", "e5", "Nf3", "Nc6"], as: .white)
        gm.undoLastTwoMoves()
        // After undoing Nf3/Nc6 the FEN must match the 2-move position
        #expect(gm.board.position.fen == fenAfterTwo)
    }

    @Test("Undo clears selected square and legal moves")
    func undoClearsSelection() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["e4", "e5", "Nf3", "Nc6"], as: .white)
        gm.handleSquareTap(Square("f3"))   // select the knight
        #expect(gm.selectedSquare != nil)
        gm.undoLastTwoMoves()
        #expect(gm.selectedSquare == nil)
        #expect(gm.legalMoveSquares.isEmpty)
    }

    @Test("Undo resets isWaitingForBot to false")
    func undoResetsWaiting() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["e4", "e5", "Nf3", "Nc6"], as: .white)
        gm.isWaitingForBot = true
        gm.undoLastTwoMoves()
        #expect(!gm.isWaitingForBot)
    }

    @Test("Multiple consecutive undos work correctly")
    func multipleUndos() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5"], as: .white)
        gm.undoLastTwoMoves()   // → 4 moves left
        gm.undoLastTwoMoves()   // → 2 moves left
        gm.undoLastTwoMoves()   // → no-op (< 2 would be 0, but 2 remain so this succeeds)
        #expect(gm.moveHistory.count == 0)
    }
}

// MARK: - BoardTheme

@Suite("BoardTheme")
struct BoardThemeTests {

    @Test("All raw values round-trip through BoardTheme(rawValue:)")
    func rawValueRoundTrip() {
        for theme in BoardTheme.allCases {
            let recovered = BoardTheme(rawValue: theme.rawValue)
            #expect(recovered == theme)
        }
    }

    @Test("Classic theme has distinct light and dark square colours")
    func classicColours() {
        let t = BoardTheme.classic
        #expect(t.lightSquare != t.darkSquare)
    }

    @Test("Green theme has distinct light and dark square colours")
    func greenColours() {
        let t = BoardTheme.green
        #expect(t.lightSquare != t.darkSquare)
    }

    @Test("Blue theme has distinct light and dark square colours")
    func blueColours() {
        let t = BoardTheme.blue
        #expect(t.lightSquare != t.darkSquare)
    }

    @Test("All themes have non-nil displayName")
    func displayNames() {
        for theme in BoardTheme.allCases {
            #expect(!theme.displayName.isEmpty)
        }
    }

    @Test("allCases contains exactly Classic, Green, and Blue")
    func allCasesCount() {
        #expect(BoardTheme.allCases.count == 3)
        let names = Set(BoardTheme.allCases.map(\.rawValue))
        #expect(names == ["classic", "green", "blue"])
    }
}

// MARK: - VoiceMoveParser: captures and additional patterns

@Suite("VoiceMoveParser – captures and additional patterns")
struct CaptureParseTests {

    @Test("'pawn takes e five' is recognized as exd5 equivalent capture (e4 exd5 scenario)")
    func pawnCapture() throws {
        // 1. e4 d5 — White pawn on e4 can capture pawn on d5
        var b = Board()
        _ = b.move(pieceAt: Square("e2"), to: Square("e4"))
        _ = b.move(pieceAt: Square("d7"), to: Square("d5"))

        let result = VoiceMoveParser.parse(
            transcription: "pawn takes d five",
            board: b,
            playerColor: .white
        )
        let move = try #require(result, "Should parse pawn capture on d5")
        #expect(move.start == Square("e4"))
        #expect(move.end   == Square("d5"))
    }

    @Test("'e takes d five' is recognized (file notation for pawn capture)")
    func pawnCaptureFileNotation() throws {
        var b = Board()
        _ = b.move(pieceAt: Square("e2"), to: Square("e4"))
        _ = b.move(pieceAt: Square("d7"), to: Square("d5"))

        let result = VoiceMoveParser.parse(
            transcription: "e takes d five",
            board: b,
            playerColor: .white
        )
        let move = try #require(result)
        #expect(move.start == Square("e4"))
        #expect(move.end   == Square("d5"))
    }

    @Test("'bishop to c four' is recognized in Italian opening")
    func bishopToC4() throws {
        var b = Board()
        _ = b.move(pieceAt: Square("e2"), to: Square("e4"))
        _ = b.move(pieceAt: Square("e7"), to: Square("e5"))
        _ = b.move(pieceAt: Square("g1"), to: Square("f3"))
        _ = b.move(pieceAt: Square("b8"), to: Square("c6"))

        let result = VoiceMoveParser.parse(
            transcription: "bishop to c four",
            board: b,
            playerColor: .white
        )
        let move = try #require(result)
        #expect(move.start == Square("f1"))
        #expect(move.end   == Square("c4"))
    }

    @Test("'rock to e one' (homophone) moves rook to e1")
    func rookHomophone() throws {
        // Rook on a1, King on h1, Black King on d6 — rank 1 is clear between a1 and h1.
        // The rook can legally move to e1 with an unobstructed path.
        let b = Board(position: Position(
            fen: "8/8/3k4/8/8/8/8/R6K w - - 0 1"
        )!)

        let result = VoiceMoveParser.parse(
            transcription: "rock to e one",
            board: b,
            playerColor: .white
        )
        let move = try #require(result, "Should parse 'rock' as 'rook'")
        #expect(b.position.piece(at: move.start)?.kind == .rook)
        #expect(move.end == Square("e1"))
    }

    @Test("'queen to d one' moves queen on custom board")
    func queenMove() throws {
        // Custom position: White queen on d5, can go to d1
        var b = Board(position: Position(
            fen: "8/8/8/3Q4/8/8/8/4K3 w - - 0 1"
        )!)
        let result = VoiceMoveParser.parse(
            transcription: "queen to d one",
            board: b,
            playerColor: .white
        )
        let move = try #require(result)
        #expect(b.position.piece(at: move.start)?.kind == .queen)
        #expect(move.end == Square("d1"))
    }
}

// MARK: - MoveNarrator: additional cases

@Suite("MoveNarrator – additional cases")
struct MoveNarratorAdditionalTests {

    @Test("Rook move is narrated as 'Rook to <square>'")
    func rookMove() throws {
        // Rook on a1, both kings present, Black King on f6 — out of check range
        // so Ra1-a8 is a plain rook move with no check or stalemate.
        var b = Board(position: Position(
            fen: "8/8/5k2/8/8/8/8/R3K3 w - - 0 1"
        )!)
        let rookMove = b.move(pieceAt: Square("a1"), to: Square("a8"))
        let move = try #require(rookMove)
        let text = MoveNarrator.narrate(move: move)
        #expect(text == "Rook to a eight.")
    }

    @Test("Bishop capture is narrated as 'Bishop takes <square>'")
    func bishopCapture() throws {
        // After 1.e4 e5 2.Bc4: d5 and e6 are empty, f7 has a Black pawn.
        // Bxf7+ is a legal capture that also gives check (bishop attacks e8 from f7).
        var b = Board(position: Position(
            fen: "rnbqkbnr/pppp1ppp/8/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq e6 0 3"
        )!)
        let captureMove = b.move(pieceAt: Square("c4"), to: Square("f7"))
        let move = try #require(captureMove, "Bishop on c4 should be able to capture the pawn on f7")
        let text = MoveNarrator.narrate(move: move)
        #expect(text.hasPrefix("Bishop takes f seven"))
    }

    @Test("Queenside castle is narrated correctly")
    func queensideCastle() throws {
        var b = Board(position: Position(
            fen: "r3kbnr/pppqpppp/2np4/4P3/3P4/2NB1N2/PPP2PPP/R3K2R w KQkq - 1 7"
        )!)
        let castleMove = b.move(pieceAt: Square("e1"), to: Square("c1"))
        let move = try #require(castleMove)
        let text = MoveNarrator.narrate(move: move)
        #expect(text == "Castle queenside.")
    }

    @Test("Check is appended after the move description")
    func checkAppended() throws {
        // Queen on f5, Black King on e8, White King on e1.
        // Qf5-f8 moves along the f-file and delivers check to the king on e8
        // (queen controls the entire 8th rank from f8).
        var b = Board(position: Position(
            fen: "4k3/8/8/5Q2/8/8/8/4K3 w - - 0 1"
        )!)
        let checkMove = b.move(pieceAt: Square("f5"), to: Square("f8"))
        let move = try #require(checkMove)
        let text = MoveNarrator.narrate(move: move)
        #expect(text.contains("Check"), "Narration should mention Check when king is in check")
    }
}

// MARK: - AnalysisScore

@Suite("AnalysisScore – displayString and barFraction")
struct AnalysisScoreTests {

    @Test("Centipawns: positive displays with '+' prefix")
    func positiveCP() {
        let score = AnalysisScore.centipawns(150)
        #expect(score.displayString == "+1.5")
    }

    @Test("Centipawns: zero displays as '+0.0'")
    func zeroCP() {
        let score = AnalysisScore.centipawns(0)
        #expect(score.displayString == "+0.0")
    }

    @Test("Centipawns: negative displays without '+' prefix")
    func negativeCP() {
        let score = AnalysisScore.centipawns(-75)
        #expect(score.displayString == "-0.8")
    }

    @Test("Mate: positive displays as 'M<n>'")
    func whiteMateIn3() {
        let score = AnalysisScore.mate(3)
        #expect(score.displayString == "M3")
    }

    @Test("Mate: negative displays as '-M<n>'")
    func blackMateIn2() {
        let score = AnalysisScore.mate(-2)
        #expect(score.displayString == "-M2")
    }

    @Test("barFraction: equal position is ~0.5")
    func barFractionEqual() {
        let score = AnalysisScore.centipawns(0)
        #expect(abs(score.barFraction - 0.5) < 0.001)
    }

    @Test("barFraction: large White advantage is above 0.5")
    func barFractionWhiteAdvantage() {
        let score = AnalysisScore.centipawns(500)
        #expect(score.barFraction > 0.5)
    }

    @Test("barFraction: large Black advantage is below 0.5")
    func barFractionBlackAdvantage() {
        let score = AnalysisScore.centipawns(-500)
        #expect(score.barFraction < 0.5)
    }

    @Test("barFraction: White mate is 0.96")
    func barFractionWhiteMate() {
        let score = AnalysisScore.mate(1)
        #expect(score.barFraction == 0.96)
    }

    @Test("barFraction: Black mate is 0.04")
    func barFractionBlackMate() {
        let score = AnalysisScore.mate(-1)
        #expect(score.barFraction == 0.04)
    }

    @Test("barFraction is bounded between 0 and 1 for extreme CP values")
    func barFractionBounded() {
        let huge = AnalysisScore.centipawns(100_000)
        let tiny = AnalysisScore.centipawns(-100_000)
        #expect(huge.barFraction <= 1.0)
        #expect(tiny.barFraction >= 0.0)
    }
}

// MARK: - Voice commands: "undo", "repeat", and move readback

@Suite("VoiceMoveParser – normalize: undo / repeat commands")
struct VoiceCommandNormalizeTests {

    @Test("'undo' normalises to the word 'undo'")
    func undoNormalisesCorrectly() {
        let result = VoiceMoveParser.normalize("undo")
        #expect(result.split(separator: " ").map(String.init).contains("undo"))
    }

    @Test("'undo that' still contains the word 'undo' after normalisation")
    func undoThatNormalisesCorrectly() {
        let words = VoiceMoveParser.normalize("undo that").split(separator: " ").map(String.init)
        #expect(words.contains("undo"))
    }

    @Test("'undo my move' still contains 'undo' after noise-word filtering")
    func undoMyMoveNormalisesCorrectly() {
        // "my" and "move" are noise words, so only "undo" should remain
        let words = VoiceMoveParser.normalize("undo my move").split(separator: " ").map(String.init)
        #expect(words.contains("undo"))
        #expect(!words.contains("my"))
        #expect(!words.contains("move"))
    }

    @Test("'repeat' normalises to the word 'repeat'")
    func repeatNormalisesCorrectly() {
        let result = VoiceMoveParser.normalize("repeat")
        #expect(result.split(separator: " ").map(String.init).contains("repeat"))
    }

    @Test("'again' normalises to the word 'again'")
    func againNormalisesCorrectly() {
        let result = VoiceMoveParser.normalize("again")
        #expect(result.split(separator: " ").map(String.init).contains("again"))
    }

    @Test("'say that again' contains 'again' after normalisation")
    func sayThatAgain() {
        let words = VoiceMoveParser.normalize("say that again").split(separator: " ").map(String.init)
        #expect(words.contains("again"))
    }

    @Test("'undo' does not parse as a chess move (returns nil)")
    func undoDoesNotParseAsMove() {
        let result = VoiceMoveParser.parse(
            transcription: "undo",
            board: Board(),
            playerColor: .white
        )
        #expect(result == nil, "'undo' should not match any legal chess move")
    }

    @Test("'repeat' does not parse as a chess move (returns nil)")
    func repeatDoesNotParseAsMove() {
        let result = VoiceMoveParser.parse(
            transcription: "repeat",
            board: Board(),
            playerColor: .white
        )
        #expect(result == nil, "'repeat' should not match any legal chess move")
    }
}

@Suite("MoveNarrator – player echo readback phrases")
struct PlayerEchoTests {

    /// Mimics `GameView.buildPlayerEcho` — pure string logic, no board mutations.
    private func echoPhrase(transcription: String, checkState: Move.CheckState) -> String {
        let base = transcription.trimmingCharacters(in: .whitespaces)
        switch checkState {
        case .checkmate: return "\(base). Checkmate"
        case .check:     return "\(base). Check"
        case .stalemate: return "\(base). Stalemate"
        case .none:      return base
        }
    }

    @Test("Plain move echoes the raw transcription unchanged (.none checkState)")
    func plainMoveEcho() {
        let echo = echoPhrase(transcription: "e four", checkState: .none)
        #expect(echo == "e four")
    }

    @Test("'castles' echoes as 'castles' with no suffix (.none checkState)")
    func castlesEcho() {
        let echo = echoPhrase(transcription: "castles", checkState: .none)
        #expect(echo == "castles")
    }

    @Test("Check annotation is appended correctly")
    func checkAnnotation() {
        let echo = echoPhrase(transcription: "queen f eight", checkState: .check)
        #expect(echo == "queen f eight. Check")
    }

    @Test("Checkmate annotation is appended correctly")
    func checkmateAnnotation() {
        let echo = echoPhrase(transcription: "queen h five", checkState: .checkmate)
        #expect(echo == "queen h five. Checkmate")
    }

    @Test("Stalemate annotation is appended correctly")
    func stalemateAnnotation() {
        let echo = echoPhrase(transcription: "king e two", checkState: .stalemate)
        #expect(echo == "king e two. Stalemate")
    }

    @Test("Echo phrase differs from formal MoveNarrator output")
    func echoIsDifferentFromFormalNarration() {
        // MoveNarrator says "Knight to f three." — echo should preserve what the user said.
        var b = Board()
        let moveResult = b.move(pieceAt: Square("g1"), to: Square("f3"))
        guard let move = moveResult else {
            Issue.record("Unexpected nil move from g1 to f3")
            return
        }
        let formal = MoveNarrator.narrate(move: move)
        let echo   = echoPhrase(transcription: "night f three", checkState: move.checkState)
        #expect(echo == "night f three")
        #expect(formal == "Knight to f three.")
        #expect(echo != formal)
    }

    @Test("Combined player echo + bot narration string is well-formed")
    func combinedEchoAndBotNarration() {
        let echo = "castles"
        let botNarration = "Knight f six."
        let fullSpeech = "\(echo). \(botNarration)"
        #expect(fullSpeech == "castles. Knight f six.")
    }

    @Test("Empty pending echo produces only bot narration (no leading separator)")
    func emptyEchoProducesOnlyBotNarration() {
        let echo = ""
        let botNarration = "E four."
        let fullSpeech = echo.isEmpty ? botNarration : "\(echo). \(botNarration)"
        #expect(fullSpeech == "E four.")
    }
}

@Suite("GameManager – undo via voice (edge cases)")
@MainActor
struct VoiceUndoTests {

    @Test("Undo while game is over resets outcome to ongoing")
    func undoAfterGameOver() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["e4", "e5", "Nf3", "Nc6"], as: .white)
        gm.resign()
        #expect(gm.isGameOver)
        gm.undoLastTwoMoves()
        #expect(!gm.isGameOver)
        #expect(gm.outcome == .ongoing)
    }

    @Test("Undo with exactly 2 moves leaves an empty history")
    func undoExactlyTwoMoves() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["e4", "e5"], as: .white)
        gm.undoLastTwoMoves()
        #expect(gm.moveHistory.isEmpty)
    }

    @Test("Undo preserves the player color")
    func undoPreservesPlayerColor() {
        let gm = GameManager(playerColor: .black)
        gm.restoreGame(moveSANs: ["d4", "d5", "c4", "c5"], as: .black)
        gm.undoLastTwoMoves()
        #expect(gm.playerColor == .black)
    }

    @Test("Undo with one move is a no-op (guard protects it)")
    func undoOneMoveBoundary() {
        let gm = GameManager(playerColor: .white)
        gm.restoreGame(moveSANs: ["e4"], as: .white)
        gm.undoLastTwoMoves()
        #expect(gm.moveHistory.count == 1, "Should not undo when fewer than 2 moves exist")
    }
}
