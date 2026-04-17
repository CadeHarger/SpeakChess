import SwiftUI
import ChessKit

// MARK: - Board theme

/// Three colour palettes for the 8×8 grid.
/// The raw value matches the "boardTheme" AppStorage key.
enum BoardTheme: String, CaseIterable, Identifiable {
    case classic
    case green
    case blue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .green:   "Green"
        case .blue:    "Blue"
        }
    }

    var lightSquare: Color {
        switch self {
        case .classic: Color(red: 0.937, green: 0.875, blue: 0.780)  // cream
        case .green:   Color(red: 0.933, green: 0.933, blue: 0.824)  // #eeeed2
        case .blue:    Color(red: 0.871, green: 0.890, blue: 0.902)  // #dee3e6
        }
    }

    var darkSquare: Color {
        switch self {
        case .classic: Color(red: 0.576, green: 0.447, blue: 0.337)  // walnut
        case .green:   Color(red: 0.463, green: 0.588, blue: 0.337)  // #769656
        case .blue:    Color(red: 0.549, green: 0.635, blue: 0.678)  // #8ca2ad
        }
    }

    var selectedLight: Color {
        switch self {
        case .classic: Color(red: 0.95, green: 0.93, blue: 0.38)
        case .green:   Color(red: 0.85, green: 0.90, blue: 0.30)
        case .blue:    Color(red: 0.80, green: 0.87, blue: 0.95)
        }
    }

    var selectedDark: Color {
        switch self {
        case .classic: Color(red: 0.73, green: 0.71, blue: 0.18)
        case .green:   Color(red: 0.62, green: 0.74, blue: 0.18)
        case .blue:    Color(red: 0.46, green: 0.60, blue: 0.78)
        }
    }

    var lastMoveLight: Color {
        switch self {
        case .classic: Color(red: 0.95, green: 0.93, blue: 0.55)
        case .green:   Color(red: 0.87, green: 0.92, blue: 0.50)
        case .blue:    Color(red: 0.85, green: 0.90, blue: 0.95)
        }
    }

    var lastMoveDark: Color {
        switch self {
        case .classic: Color(red: 0.73, green: 0.71, blue: 0.33)
        case .green:   Color(red: 0.60, green: 0.73, blue: 0.33)
        case .blue:    Color(red: 0.55, green: 0.67, blue: 0.78)
        }
    }
}

// MARK: - ChessBoardView

struct ChessBoardView: View {
    let board: Board
    let playerColor: Piece.Color
    let selectedSquare: Square?
    let legalMoveSquares: [Square]
    let lastMove: Move?
    let onSquareTap: (Square) -> Void

    @AppStorage("boardTheme") private var boardThemeRaw = "classic"
    private var theme: BoardTheme { BoardTheme(rawValue: boardThemeRaw) ?? .classic }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let sqSize = size / 8

            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { col in
                            let sq = mapSquare(row: row, col: col)
                            BoardSquareCell(
                                square: sq,
                                piece: board.position.piece(at: sq),
                                isSelected: sq == selectedSquare,
                                isLegalTarget: legalMoveSquares.contains(sq),
                                isLastMove: sq == lastMove?.start || sq == lastMove?.end,
                                isInCheck: isKingInCheck(sq),
                                showRankLabel: col == 0,
                                showFileLabel: row == 7,
                                size: sqSize,
                                theme: theme
                            )
                            .onTapGesture { onSquareTap(sq) }
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // Maps screen (row, col) to a chess square, accounting for board flip
    private func mapSquare(row: Int, col: Int) -> Square {
        let fileNum = playerColor == .white ? col + 1 : 8 - col
        let rankNum  = playerColor == .white ? 8 - row : row + 1
        // Square.init(File,Rank) is internal; build the notation string instead
        let fileChar = Square.File(fileNum).rawValue
        return Square("\(fileChar)\(rankNum)")
    }

    // Highlight the king's square red when in check
    private func isKingInCheck(_ sq: Square) -> Bool {
        guard case .check(let color) = board.state else { return false }
        guard let piece = board.position.piece(at: sq),
              piece.kind == .king,
              piece.color == color else { return false }
        return true
    }
}

// MARK: - Individual square

private struct BoardSquareCell: View {

    let square: Square
    let piece: Piece?
    let isSelected: Bool
    let isLegalTarget: Bool
    let isLastMove: Bool
    let isInCheck: Bool
    let showRankLabel: Bool
    let showFileLabel: Bool
    let size: CGFloat
    let theme: BoardTheme

    private var isLight: Bool { square.color == .light }
    private let checkRed = Color(red: 0.85, green: 0.22, blue: 0.22)

    var body: some View {
        ZStack {
            // Background
            background
                .frame(width: size, height: size)

            // Legal-move indicator
            if isLegalTarget {
                if piece != nil {
                    // Ring around an occupied square (capture target)
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.black.opacity(0.30), lineWidth: size * 0.08)
                        .padding(size * 0.04)
                } else {
                    // Dot on an empty target square
                    Circle()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: size * 0.32, height: size * 0.32)
                }
            }

            // Piece
            if let p = piece {
                Text(p.unicodeSymbol)
                    .font(.system(size: size * 0.72))
                    .shadow(color: .black.opacity(0.20), radius: 1, x: 0, y: 1)
            }

            // Coordinate labels
            if showRankLabel {
                Text("\(square.rank.value)")
                    .font(.system(size: size * 0.21, weight: .semibold))
                    .foregroundStyle(isLight ? theme.darkSquare : theme.lightSquare)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(size * 0.06)
            }
            if showFileLabel {
                Text(square.file.rawValue)
                    .font(.system(size: size * 0.21, weight: .semibold))
                    .foregroundStyle(isLight ? theme.darkSquare : theme.lightSquare)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(size * 0.06)
            }
        }
    }

    private var background: Color {
        if isInCheck  { return checkRed }
        if isSelected { return isLight ? theme.selectedLight  : theme.selectedDark }
        if isLastMove { return isLight ? theme.lastMoveLight  : theme.lastMoveDark }
        return isLight ? theme.lightSquare : theme.darkSquare
    }
}

// MARK: - Piece → Unicode symbol

extension Piece {
    var unicodeSymbol: String {
        switch (color, kind) {
        case (.white, .king):   "♔"
        case (.white, .queen):  "♕"
        case (.white, .rook):   "♖"
        case (.white, .bishop): "♗"
        case (.white, .knight): "♘"
        case (.white, .pawn):   "♙"
        case (.black, .king):   "♚"
        case (.black, .queen):  "♛"
        case (.black, .rook):   "♜"
        case (.black, .bishop): "♝"
        case (.black, .knight): "♞"
        case (.black, .pawn):   "♟"
        }
    }
}
