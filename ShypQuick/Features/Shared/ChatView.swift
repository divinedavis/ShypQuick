import SwiftUI

struct ChatView: View {
    let isDriver: Bool
    @StateObject private var chat = ChatService.shared
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(chat.messages) { msg in
                            let isMe = msg.isFromDriver == isDriver
                            HStack {
                                if isMe { Spacer(minLength: 60) }
                                VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                                    Text(msg.text)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(isMe ? Color.accentColor : Color(.systemGray5),
                                                     in: RoundedRectangle(cornerRadius: 16))
                                        .foregroundStyle(isMe ? .white : .primary)
                                    Text(msg.sentAt, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if !isMe { Spacer(minLength: 60) }
                            }
                            .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Message…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(isDriver ? "Customer" : "Driver")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendMessage() {
        chat.send(draft, isFromDriver: isDriver)
        draft = ""
    }
}
