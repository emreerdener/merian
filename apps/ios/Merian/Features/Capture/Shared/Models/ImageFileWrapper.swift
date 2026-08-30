import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImageFileWrapper: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { wrapper in
            SentTransferredFile(wrapper.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let tempDst = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: tempDst)
            return Self(url: tempDst)
        }
    }
}
