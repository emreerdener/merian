import SwiftData
import SwiftUI

struct UserTagsCard: View {
    let scanId: String

    @Environment(\.modelContext) private var modelContext
    @Query private var records: [LocalScanRecord]
    @State private var viewModel: UserTagsViewModel

    @State private var showingAddTagAlert = false
    @State private var newTagText = ""
    init(
        scanId: String,
        dependencies: UserTagsDependencies? = nil
    ) {
        self.scanId = scanId
        self._records = Query(filter: #Predicate<LocalScanRecord> { $0.id == scanId })
        _viewModel = State(
            initialValue: UserTagsViewModel(dependencies: dependencies)
        )
    }

    var record: LocalScanRecord? {
        records.first
    }

    var body: some View {
        if let record = record {
            UserTagsCardContent(
                tags: record.customTags,
                errorMessage: viewModel.errorMessage,
                onAddTapped: presentAddTagAlert,
                onRemoveTag: { removeTag($0, from: record) }
            )
            .alert("Add Tag", isPresented: $showingAddTagAlert) {
                TextField("e.g. backyard, summer", text: $newTagText)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { }
                Button("Add") {
                    addTag(newTagText, to: record)
                }
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Add a custom tag to easily search for this scan later.")
            }
        }
    }

    private func presentAddTagAlert() {
        newTagText = ""
        showingAddTagAlert = true
    }

    // MARK: - Mutable Logic
    private func addTag(_ tag: String, to record: LocalScanRecord) {
        viewModel.addTag(
            tag,
            to: record,
            modelContext: modelContext
        )
    }

    private func removeTag(_ tag: String, from record: LocalScanRecord) {
        viewModel.removeTag(
            tag,
            from: record,
            modelContext: modelContext
        )
    }
}

private struct UserTagsCardContent: View {
    let tags: [String]
    let errorMessage: String?
    let onAddTapped: () -> Void
    let onRemoveTag: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MerianCardHeader(systemImage: "tag", title: "Tags") {
                Spacer()

                Button(action: onAddTapped) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .imageScale(.large)
                        .foregroundColor(.accentColor)
                }
            }

            if tags.isEmpty {
                emptyState
            } else {
                tagList
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
        .card()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No custom tags added. Add tags to easily find this scan later.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: onAddTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add tag")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var tagList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.subheadline)

                        Button {
                            onRemoveTag(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.8))
                                .imageScale(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
        }
    }
}
