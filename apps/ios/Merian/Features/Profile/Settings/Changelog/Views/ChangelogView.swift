import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ChangelogView: View {
    @State private var store = ChangelogStore()

    var body: some View {
        List {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No changelog yet",
                    systemImage: "sparkles.rectangle.stack",
                    description: Text("Release notes will appear here when they are added to the app.")
                )
            } else {
                ForEach(store.entries) { entry in
                    ChangelogEntryRow(entry: entry)
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Changelog")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChangelogEntryRow: View {
    let entry: ChangelogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(entry.formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let imageAssetName = entry.imageAssetName {
                ChangelogImage(assetName: imageAssetName)
            }

            ForEach(entry.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(section.items, id: \.self) { item in
                            ChangelogBullet(text: item)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ChangelogImage: View {
    let assetName: String

    var body: some View {
        if assetExists {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var assetExists: Bool {
        #if canImport(UIKit)
        UIImage(named: assetName) != nil
        #else
        true
        #endif
    }
}

private struct ChangelogBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        ChangelogView()
    }
}
