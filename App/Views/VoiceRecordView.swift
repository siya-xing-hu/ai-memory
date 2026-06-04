import SwiftUI
import AVFoundation

struct VoiceRecordView: View {
    let onComplete: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var transcribedText = ""
    @State private var showTranscription = false
    @State private var audioURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                if showTranscription {
                    TextEditor(text: $transcribedText)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .frame(height: 200)
                        .padding(.horizontal)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 80))
                            .foregroundColor(isRecording ? .red : .blue)
                            .symbolEffect(.pulse, isActive: isRecording)

                        Text(isRecording ? "录音中..." : "点击开始录音")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 30) {
                    Button("取消") {
                        stopRecording()
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundColor(.secondary)

                    Button(action: toggleRecording) {
                        Image(systemName: isRecording ? "stop.fill" : "mic.circle.fill")
                            .font(.system(size: 72))
                            .foregroundColor(isRecording ? .red : .blue)
                    }

                    if showTranscription {
                        Button("保存") {
                            onComplete(transcribedText)
                            dismiss()
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                    } else {
                        Spacer().frame(width: 50)
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("语音记录")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
            showTranscription = true
            transcribedText = "（此处为模拟语音转文字结果，实际需接入语音识别服务）"
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return }
        self.recorder = recorder
        self.audioURL = url
        recorder.record()
        isRecording = true
    }

    private func stopRecording() {
        recorder?.stop()
        isRecording = false
    }
}
