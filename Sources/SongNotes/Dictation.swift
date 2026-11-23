import AVFoundation
import Speech

/// Mic button: on-device speech-to-text that appends to the note.
@MainActor
final class Dictation: ObservableObject {
    @Published var isRecording = false
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func toggle(base: String, update: @escaping (String) -> Void) {
        if isRecording { stop() } else { Task { await start(base: base, update: update) } }
    }

    private func start(base: String, update: @escaping (String) -> Void) async {
        error = nil
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVCaptureDevice.requestAccess(for: .audio)
        guard speechOK, micOK else {
            error = "Allow Microphone and Speech Recognition for SongNotes in System Settings › Privacy & Security."
            return
        }
        guard let recognizer, recognizer.isAvailable else { error = "Speech recognition unavailable."; return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in req.append(buf) }
        engine.prepare()
        do { try engine.start() } catch { self.error = error.localizedDescription; return }
        isRecording = true

        let prefix = base.isEmpty ? "" : base.trimmingCharacters(in: .whitespaces) + " "
        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            Task { @MainActor in
                if let result { update(prefix + result.bestTranscription.formattedString) }
                if err != nil || (result?.isFinal ?? false) { self?.stop() }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isRecording = false
    }
}
