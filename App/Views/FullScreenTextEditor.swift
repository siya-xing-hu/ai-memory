import SwiftUI

struct FullScreenTextEditor: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .focused($isFocused)
                .padding(8)
                .navigationTitle("编辑内容")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            text = draft
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    draft = text
                    isFocused = true
                }
        }
    }
}
