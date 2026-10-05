import PhotosUI
import SwiftUI

struct CaptureReanalysisSheet: View {
    @Bindable var editor: CaptureReanalysisEditor
    let close: () -> Void
    @State private var selectedImport: PhotosPickerItem?
    @State private var preview: ObservationHistoryPhotoReference?
    @State private var confirmsDiscard = false

    var body: some View {
        NavigationStack {
            List {
                if editor.phase == .saved {
                    Section {
                        Label("Reanalysis draft saved", systemImage: "checkmark.circle")
                        Text("Your current identification is unchanged. This draft is saved for processing.")
                    }
                } else if editor.phase == .choosing {
                    originalPhotos
                } else if editor.phase == .editing {
                    evidenceEditor
                }
                if let error = editor.errorMessage {
                    Section { Text(error).foregroundStyle(.secondary) }
                }
                if editor.isBusy { ProgressView().accessibilityLabel("Preparing reanalysis") }
            }
            .navigationTitle("Reanalyze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editor.phase == .saved ? "Done" : "Cancel") {
                        if editor.phase == .saved { close() } else { confirmsDiscard = true }
                    }
                    .disabled(editor.isBusy)
                }
            }
            .confirmationDialog("Discard this reanalysis draft?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) { if editor.discard() { close() } }
                Button("Keep editing", role: .cancel) { }
            } message: { Text("Your original identification and other results will be kept.") }
            .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
                if let photo = preview { CaptureReanalysisPhotoPreview(editor: editor, photo: photo) }
            }
            .onChange(of: editor.phase) { _, phase in
                if phase == .closed {
                    selectedImport = nil; preview = nil; confirmsDiscard = false
                }
            }
            .task(id: selectedImport) {
                guard let item = selectedImport else { return }
                await editor.importPhoto(item)
                selectedImport = nil
            }
        }
        .interactiveDismissDisabled()
    }

    private var originalPhotos: some View {
        Section {
            Text("Choose the original photos to include. You can review them and add new photos next.")
            ForEach(Array(editor.photos.enumerated()), id: \.element.mediaID) { index, photo in
                HStack {
                    Button { editor.toggle(photo.mediaID) } label: {
                        Label("Photo \(index + 1)", systemImage: editor.selectedPhotoIDs.contains(photo.mediaID) ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("Preview") { preview = photo }.buttonStyle(.borderless)
                }
                .disabled(editor.isBusy)
            }
            if editor.photos.isEmpty { Text("Add new photos on the next screen.").foregroundStyle(.secondary) }
            Button("Continue") { Task { await editor.loadSelection() } }.disabled(editor.isBusy)
        } footer: { Text("Up to five photos. The identification you opened will remain the source even if your library selection changes.") }
    }

    private var evidenceEditor: some View {
        Group {
            Section("Photos") {
                ForEach(editor.capture.images, id: \.original.id) { image in
                    HStack {
                        Image(uiImage: image.uiImage).resizable().scaledToFit().frame(height: 100)
                        Spacer()
                        Button("Remove", role: .destructive) { editor.removePhoto(image.original.id) }.disabled(!editor.canEdit)
                    }
                }
                PhotosPicker(selection: $selectedImport, matching: .images) { Label("Add photo", systemImage: "photo.badge.plus") }
                    .disabled(!editor.canEdit || editor.capture.images.count >= 5)
            }
            Section("Notes") {
                ForEach(editor.capture.observationContexts.indices, id: \.self) { index in
                    TextEditor(text: Binding(get: {
                        editor.capture.observationContexts.indices.contains(index) ? editor.capture.observationContexts[index].context.freeText : ""
                    }, set: { editor.setNote($0, at: index) }))
                        .frame(minHeight: 70).disabled(!editor.canEdit)
                    Button("Remove note", role: .destructive) { editor.removeNote(at: index) }.disabled(!editor.canEdit)
                }
                Button("Add note") { editor.addNote() }.disabled(!editor.canEdit)
            }
            Section {
                Button(editor.isFrozen ? "Retry saving draft" : "Save reanalysis draft") { Task { await editor.save() } }
                    .disabled(!editor.canSave)
            } footer: { Text("Saving preserves your current identification. A new result will be added to its history after processing.") }
        }
    }
}

private struct CaptureReanalysisPhotoPreview: View {
    let editor: CaptureReanalysisEditor
    let photo: ObservationHistoryPhotoReference
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if editor.phase == .closed { Color.clear } else if let image { Image(uiImage: image).resizable().scaledToFit() } else if failed { Text("This original photo is unavailable for reanalysis. Choose another or add a new photo.").padding() } else { ProgressView() }
        }
        .onChange(of: editor.phase) { _, phase in
            if phase == .closed { image = nil; failed = false }
        }
        .task {
            do {
                let loaded = try await editor.preview(photo)
                guard !Task.isCancelled, editor.phase != .closed else { return }
                image = loaded
            } catch {
                if !Task.isCancelled, editor.phase != .closed { failed = true }
            }
        }
    }
}
