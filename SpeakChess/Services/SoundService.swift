import AudioToolbox
import Foundation

/// Plays short system sounds to give audio feedback on game events.
/// All methods are safe to call from any thread.
/// Respects the "soundEnabled" UserDefaults flag written by SettingsView.
final class SoundService {

    static let shared = SoundService()
    private init() {}

    private var isEnabled: Bool {
        // Defaults to true if the key has never been written.
        UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    }

    // MARK: - Public events

    /// Soft click — normal piece placement.
    func playMove() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1057)       // keyboard-click-delete (subtle)
    }

    /// Sharper click — piece captures another.
    func playCapture() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1108)       // jbl_confirm (heavier)
    }

    /// Alert tone — king put in check.
    func playCheck() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1022)       // SIMToolkitGeneralBeep
    }

    /// Completion sound — checkmate, resignation, or draw.
    func playGameEnd() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1001)       // mail-sent (satisfying ding)
    }
}
