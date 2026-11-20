import SwiftUI

struct ProtectedInsightChatSheet: View {
    @Bindable var model: ProtectedInsightChatModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if let message = model.message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("ProtectedChatStatus") }
                if model.requiresIdentificationRefresh {
                    Button("Refresh identification") { model.refreshIdentification() }
                        .disabled(!model.canRefreshIdentification)
                        .accessibilityIdentifier("ProtectedChatRefreshIdentification")
                    if model.isRefreshingIdentification { ProgressView("Refreshing identification…") }
                }
                if model.canRetrySave {
                    Section("Unsaved question") {
                        Text("Your original question is kept until its save can be verified.")
                        Button("Retry saving question", action: model.retrySave).accessibilityIdentifier("ProtectedChatRetrySave")
                    }
                }
                if let pending = model.unfinished {
                    Section("Saved question") {
                        Text(pending.intent.request.messageText)
                        switch pending.state {
                        case .pending:
                            Button("Send saved question", action: model.sendSaved).accessibilityIdentifier("ProtectedChatSendSaved")
                        case .held:
                            Text("The result is not yet known. Retrying keeps this same question.").foregroundStyle(.secondary)
                            Button("Retry saved question", action: model.recoverSaved).accessibilityIdentifier("ProtectedChatRecover")
                        case .running:
                            Text("This question is being checked. You can retry it if the earlier attempt has stopped.").foregroundStyle(.secondary)
                            Button("Recover interrupted question", action: model.recoverSaved).disabled(!model.canRecover).accessibilityIdentifier("ProtectedChatRecover")
                        }
                    }.disabled(model.deliveryRequested || !model.isCurrent)
                }
                if model.unfinished == nil && !model.canRetrySave && !model.requiresIdentificationRefresh {
                    Section("Ask about this identification") {
                        TextField("Your question", text: $model.text, axis: .vertical)
                            .lineLimit(3...6).accessibilityIdentifier("ProtectedChatQuestion")
                        Button("Send question", action: model.send).disabled(!model.canSend)
                            .accessibilityIdentifier("ProtectedChatSend")
                    }
                }
                ForEach(model.completed, id: \.request.clientMessageID) { saved in
                    Section(saved.receiptKind == .notAdmitted ? "Question not sent" : "Saved reply") {
                        Text(saved.request.messageText).font(.headline)
                        if saved.receiptKind == .notAdmitted {
                            Text("The identification changed before this question could be sent.").foregroundStyle(.secondary)
                                .accessibilityIdentifier("ProtectedChatNotAdmitted")
                        } else if let data = saved.receiptData,
                           let reply = try? FieldChatResponseDecoder.decodeProtectedCompletion(data,
                               expectedSubjectId: saved.request.observationID, expectedClientMessageId: saved.request.clientMessageID) {
                            Text(reply.message.text).textSelection(.enabled)
                        }
                    }
                }
                if model.pageAfter != nil { Button("First saved replies") { model.refresh() } }
                if let next = model.next { Button("More saved replies") { model.refresh(after: next) } }
            }
            .navigationTitle("Field chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Refresh") { model.refresh(after: model.pageAfter) } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .accessibilityIdentifier("ProtectedInsightChatSheet")
        .onAppear { model.refresh() }
        .onChange(of: model.deliveryGeneration) { _, _ in model.deliveryFinished() }
        .onChange(of: model.isCurrent) { _, current in if !current { model.close(); dismiss() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh(after: model.pageAfter) } }
        .onDisappear { model.close() }
    }
}
