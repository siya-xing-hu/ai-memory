import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let onVoice: () -> Void
    let isLoading: Bool
    @State private var showFullScreenEditor = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("思考中...")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                HStack(spacing: 12) {
                    Button(action: onVoice) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red)
                            .frame(width: 36, height: 36)
                    }

                    TextField("记录点什么...", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)

                    Button(action: { showFullScreenEditor = true }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                            .frame(width: 36, height: 36)
                    }

                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(text.isEmpty ? .gray : .blue)
                    }
                    .disabled(text.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .sheet(isPresented: $showFullScreenEditor) {
                    FullScreenTextEditor(text: $text)
                }
            }
        }
        .background(Color(.systemBackground))
    }
}
