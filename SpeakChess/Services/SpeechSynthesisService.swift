import AVFoundation
import Foundation

/// Thin wrapper around AVSpeechSynthesizer.
/// `isSpeaking` is published so the GameView can pause/resume the microphone around TTS.
@MainActor
final class SpeechSynthesisService: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {

    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var speechRate: Float = 0.50   // 0.0 – 1.0, AVSpeechUtteranceDefaultSpeechRate ≈ 0.5

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    func speak(_ text: String) {
        if isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        // In the iOS Simulator the high-quality Gryphon/Vocalizer voice engines may not be
        // installed, so AVSpeechSynthesisVoice(language: "en-US") can return nil.
        // Fall back to ANY installed English voice before giving up; never fall back to a
        // non-English voice (which would cause narration in French, etc. on non-English Macs).
        let voice = AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en") })

        guard voice != nil else {
            // Signal a brief speaking cycle so onChange(of: isSpeaking) still fires.
            isSpeaking = true
            Task { @MainActor in self.isSpeaking = false }
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // Always read the latest value from UserDefaults so SettingsView changes
        // take effect immediately on the next spoken move.
        let stored = UserDefaults.standard.object(forKey: "voiceRate") as? Double
        utterance.rate = Float(max(0.1, min(1.0, stored ?? Double(speechRate))))
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Programmatic override — used when no stored preference exists yet.
    var rate: Float {
        get { speechRate }
        set { speechRate = max(0.1, min(1.0, newValue)) }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
