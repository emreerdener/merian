import SwiftUI
import UniformTypeIdentifiers

/// Explicitly supplied, already-presented host only. This view grants no fresh admission authority.
struct CaptureAudioReanalysisSheet: View {
    @Bindable var host: CaptureAudioReanalysisHost
    let preparer: CaptureAudioInputPreparer
    @State private var scope: CaptureAudioReanalysisHost.Presentation?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var before = ""
    @State private var after = ""
    @State private var showsImporter = false
    @State private var inputSelection: CaptureAudioReanalysisHost.InputSelection?

    init(host: CaptureAudioReanalysisHost, preparer: CaptureAudioInputPreparer) {
        self.host = host; self.preparer = preparer
        _scope = State(initialValue: host.presentedScope)
    }

    var body: some View {
        let selection = inputSelection
        NavigationStack {
            Form {
                if !host.matches(scope) {
                    Text("This audio presentation is no longer available.")
                } else if host.isFrozen {
                    Section {
                        Text("Your original audio input and request are retained in this session. Continuing keeps the same input and request.")
                        Button("Continue this request") {
                            guard host.matches(scope) else { return }
                            host.retry()
                        }
                        .disabled(host.isBusy).accessibilityIdentifier("AudioReanalysisContinue")
                    }
                } else {
                    Section("Audio") {
                        Button(host.preparedInput == nil ? "Choose audio file" : "Choose another audio file") {
                            guard let selection = host.beginInputSelection(scope) else { return }
                            inputSelection = selection; showsImporter = true
                        }
                        .disabled(host.isBusy || host.isPreparingInput)
                        .accessibilityIdentifier("AudioReanalysisChoose")
                        if host.preparedInput != nil {
                            Label("Audio ready", systemImage: "checkmark.circle")
                                .accessibilityIdentifier("AudioReanalysisReady")
                        }
                    }
                    Section("Optional descriptions") {
                        TextField("Before the recording", text: $before, axis: .vertical)
                            .accessibilityIdentifier("AudioReanalysisBefore")
                        TextField("After the recording", text: $after, axis: .vertical)
                            .accessibilityIdentifier("AudioReanalysisAfter")
                    }
                    .disabled(host.isBusy || host.isPreparingInput || showsImporter)
                    Button("Reanalyze audio") {
                        guard host.matches(scope) else { return }
                        host.submitPrepared(descriptionsBefore: before.isEmpty ? [] : [before],
                                            descriptionsAfter: after.isEmpty ? [] : [after])
                    }
                    .disabled(host.preparedInput == nil || host.isBusy || host.isPreparingInput || showsImporter)
                    .accessibilityIdentifier("AudioReanalysisSubmit")
                }
                if host.matches(scope) {
                    if host.isPreparingInput { ProgressView("Preparing audio") }
                    if host.isBusy { ProgressView("Checking saved request") }
                    if let message = host.message { Text(message).accessibilityIdentifier("AudioReanalysisMessage") }
                    Text("New results appear in identification history. Your current identification stays selected.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reanalyze audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { host.close(scope); dismiss() }.accessibilityIdentifier("AudioReanalysisDone")
                }
            }
        }
        .accessibilityIdentifier("AudioReanalysisSheet")
        .presentationDetents([.large])
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            guard let selection else { return }
            if inputSelection == selection { inputSelection = nil }
            let single = result.flatMap { urls -> Result<URL, Error> in
                guard urls.count == 1, let url = urls.first else { return .failure(MerianError.invalidResponse) }
                return .success(url)
            }
            host.finishInputSelection(selection, result: single, using: preparer)
        } onCancellation: {
            guard let selection else { return }
            if inputSelection == selection { inputSelection = nil }
            host.cancelInputSelection(selection)
        }
        .onChange(of: host.isCurrent, initial: true) { _, current in if !current { host.validatePresentation() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { host.validatePresentation() } }
        .onDisappear { host.close(scope) }
    }
}
