import Foundation
import Speech
import AVFoundation
import OSLog

/// Wraps SFSpeechRecognizer + AVAudioEngine for continuous, on-device voice input.
/// Audio buffers are fed via an AVAudioEngine tap; results are published for the UI
/// to observe. Each spoken utterance triggers `onFinalTranscription` exactly once.
@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SpeakChess",
        category: "SpeechRecognition"
    )

    // MARK: - State

    enum RecognitionState: Equatable {
        case idle
        case listening
        case unavailable     // hardware or permission not available
    }

    @Published var recognitionState: RecognitionState = .idle
    @Published var partialTranscription: String = ""

    /// Incremented every time a final transcription is produced.
    /// Observe this in the view using `.onChange(of:)` then read `lastFinalText`.
    @Published private(set) var finalTranscriptionCount: Int = 0
    private(set) var lastFinalText: String = ""

    // MARK: - Private

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceWorkItem: DispatchWorkItem?
    private var audioSessionPrepared = false

    override init() {
        super.init()
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Permissions

    /// Returns true if both microphone and speech recognition are authorized.
    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        return micGranted
    }

    var hasMicPermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    var hasSpeechPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Start / Stop

    func startListening() {
        guard recognitionState == .idle else { return }
        logger.debug("startListening requested")

        guard let recognizer, recognizer.isAvailable else {
            recognitionState = .unavailable
            logger.debug("speech recognizer unavailable")
            return
        }

        // Configure audio session first so isInputAvailable reflects the active category.
        // Use only .defaultToSpeaker + .allowBluetooth — omitting .duckOthers/.mixWithOthers
        // avoids option conflicts that confuse the HAL when transitioning from TTS to mic.
        let session = AVAudioSession.sharedInstance()
        if !audioSessionPrepared {
            do {
                try session.setCategory(
                    .playAndRecord,
                    mode: .measurement,
                    options: [.defaultToSpeaker, .allowBluetooth]
                )
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                audioSessionPrepared = true
            } catch {
                logger.error("failed to prepare audio session for recognition")
                return
            }
        }

        // Bail out when there is no real audio input hardware (e.g. iOS Simulator with the
        // microphone toggled off via Hardware > Microphone Disabled). Accessing inputNode
        // and installing a tap in that state throws a non-Swift NSException that crashes the app.
        guard session.isInputAvailable else {
            recognitionState = .unavailable
            logger.debug("audio input unavailable")
            return
        }

        // Build recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = request
        // On-device recognition in the simulator uses the Mac's system locale rather than the
        // recognizer's en-US locale, which causes transcriptions in French (or whatever the Mac
        // system language is). Disable the requirement in the simulator so the request always
        // goes to the server-based en-US recognizer, which correctly respects the locale.
        #if !targetEnvironment(simulator)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        #endif
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        // Install audio tap — capture `request` directly to avoid actor-isolation issues
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // A zero-channel format means the input node has no usable hardware; skip to avoid crash.
        guard format.channelCount > 0 else {
            recognitionState = .unavailable
            logger.debug("audio input format has zero channels")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [request] buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            recognitionRequest = nil
            logger.error("failed to start audio engine for recognition")
            return
        }

        recognitionState = .listening
        logger.debug("recognition started")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognitionResult(result, error: error)
            }
        }
    }

    func stopListening(cancelTask: Bool = true) {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        logger.debug("stopListening requested, cancelTask=\(cancelTask, privacy: .public)")

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // Cancel the recognition task before stopping the engine so no callbacks
        // arrive after the tap is removed.
        if cancelTask {
            recognitionTask?.cancel()
        } else {
            recognitionTask?.finish()
        }
        recognitionTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        partialTranscription = ""

        if recognitionState == .listening {
            recognitionState = .idle
        }

        // Do NOT call setActive(false) here. Deactivating the session mid-cycle
        // (between recognition and the TTS that follows) causes the Core Audio HAL
        // to crash with "Abandoning I/O cycle because reconfig pending" / "!dev".
        // The session stays active while voice mode is on; it is released in
        // releaseAudioSession(), called when voice mode is fully disabled or the
        // view disappears.
    }

    /// Releases the shared audio session. Call this only when audio is fully done
    /// (voice mode disabled or game view disappearing), never mid-cycle.
    func releaseAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        audioSessionPrepared = false
        logger.debug("audio session released")
    }

    // MARK: - Result handling

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        // Engine returned an error (usually task cancelled intentionally) — just clean up
        if error != nil {
            logger.error("recognition callback returned error")
            if recognitionState == .listening {
                stopListening()
            }
            return
        }

        guard let result else { return }

        // Drop stale callbacks that arrive after stopListening() has already been called
        // (e.g. the framework fires one final isFinal=true callback when finish() is invoked
        // by the silence timer, which would otherwise double-deliver the same transcription).
        guard recognitionState == .listening else {
            logger.debug("ignoring stale recognition callback (state=\(String(describing: self.recognitionState), privacy: .public))")
            return
        }

        let text = result.bestTranscription.formattedString
        partialTranscription = text
        logger.debug("recognition partial/final text: \(text, privacy: .public), isFinal=\(result.isFinal, privacy: .public)")

        // Cancel pending silence timer
        silenceWorkItem?.cancel()

        if result.isFinal {
            deliverFinal(text)
        } else {
            // Fire after 1.5 s of silence so the user doesn't have to wait for a speech boundary
            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.recognitionState == .listening else { return }
                    let captured = self.partialTranscription
                    self.stopListening(cancelTask: false)
                    if !captured.isEmpty {
                        self.deliverFinal(captured)
                    }
                }
            }
            silenceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
        }
    }

    private func deliverFinal(_ text: String) {
        logger.debug("deliverFinal text: \(text, privacy: .public)")
        stopListening(cancelTask: false)
        lastFinalText = text
        // Let the speech/XPC pipeline settle before game logic triggers the
        // next audio action (bot narration or mic restart).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.finalTranscriptionCount += 1
        }
    }
}
