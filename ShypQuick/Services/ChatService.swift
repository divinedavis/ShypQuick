import Foundation
import Combine

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isFromDriver: Bool
    let sentAt: Date
}

@MainActor
final class ChatService: ObservableObject {
    static let shared = ChatService()

    @Published var messages: [ChatMessage] = []

    private init() {}

    func send(_ text: String, isFromDriver: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(text: trimmed, isFromDriver: isFromDriver, sentAt: Date()))
    }

    func clear() {
        messages.removeAll()
    }
}
