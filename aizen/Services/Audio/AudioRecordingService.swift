import Foundation
import Combine
import AVFoundation

@MainActor
class AudioRecordingService: ObservableObject {
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0

    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var levelTimer: Timer?

    deinit {
        durationTimer?.invalidate()
        levelTimer?.invalidate()
    }

    // MARK: - Recording Control

    func startRecording() {
        recordingStartTime = Date()
        audioLevel = 0.0
        recordingDuration = 0

        startDurationTimer()
        startLevelMonitoring()
    }

    func stopRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        audioLevel = 0.0
        recordingDuration = 0
        recordingStartTime = nil
    }

    func cancelRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        audioLevel = 0.0
        recordingDuration = 0
        recordingStartTime = nil
    }

    // MARK: - Monitoring

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                // Simulate audio level (in real implementation, you'd get this from AVAudioRecorder metering)
                self.audioLevel = Float.random(in: 0.3...0.9)
            }
        }
    }
}
