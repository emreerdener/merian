import SwiftUI

/// Prepared explicit current-attachment entry; historical versions never supply replacement input.
struct CaptureVideoReanalysisSheet: View {
    @Bindable var host: CaptureVideoReanalysisHost
    @State private var scope: CaptureVideoReanalysisHost.Presentation?
    @State private var description = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(host: CaptureVideoReanalysisHost) {
        self.host = host
        _scope = State(initialValue: host.presentedScope)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !host.matches(scope) {
                    Text("This video presentation is no longer available.")
                } else if host.isFrozen {
                    Section {
                        Text("Continuing keeps your original video choice, description and request.")
                        Button("Continue this request") { host.retry(scope: scope) }
                            .disabled(host.isBusy)
                            .accessibilityIdentifier("VideoReanalysisContinue")
                    }
                } else {
                    Section("Current video attachment") {
                        Text("Choose the video to analyze again. Historical versions keep their original submitted content.")
                        ForEach(host.choices, id: \.mediaIndex) { choice in
                            Button {
                                host.select(choice, scope: scope)
                            } label: {
                                HStack {
                                    Text("Video \(choice.mediaIndex + 1)")
                                    Spacer()
                                    if host.selected == choice { Image(systemName: "checkmark.circle.fill") }
                                }
                            }
                            .disabled(host.isBusy)
                            .accessibilityIdentifier("VideoReanalysisChoice-\(choice.mediaIndex)")
                        }
                    }
                    Section("Optional description") {
                        TextField("About this video", text: $description, axis: .vertical)
                            .accessibilityIdentifier("VideoReanalysisDescription")
                    }
                    .disabled(host.isBusy)
                    Button("Reanalyze video") {
                        host.submit(descriptions: description.isEmpty ? [] : [description], scope: scope)
                    }
                    .disabled(host.selected == nil || host.isBusy)
                    .accessibilityIdentifier("VideoReanalysisSubmit")
                }
                if host.matches(scope) {
                    if host.isBusy { ProgressView("Checking saved request") }
                    if let message = host.message { Text(message).accessibilityIdentifier("VideoReanalysisMessage") }
                    Text("New results appear in identification history. Your current identification stays selected.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reanalyze video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { host.close(scope); dismiss() }
                        .accessibilityIdentifier("VideoReanalysisDone")
                }
            }
        }
        .accessibilityIdentifier("VideoReanalysisSheet")
        .presentationDetents([.large])
        .onChange(of: host.isCurrent, initial: true) { _, current in if !current { host.validatePresentation() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { host.validatePresentation() } }
        .onDisappear { host.close(scope) }
    }
}
