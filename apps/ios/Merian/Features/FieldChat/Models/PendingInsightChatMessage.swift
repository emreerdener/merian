import Foundation

struct PendingInsightChatMessage: Identifiable, Equatable {
    enum DeliveryState: Equatable {
        case sending
        case failed(String)
    }

    let id: String
    let text: String
    let createdAt: Date
    var deliveryState: DeliveryState = .sending

    var isSending: Bool {
        if case .sending = deliveryState { return true }
        return false
    }
}
