import Photos
import PhotosUI
import SwiftUI

struct PhotoLibraryButton: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    let latestThumbnail: UIImage?
    var maxSelectionCount: Int = 1
    var isAvailable = true
    let onRequestPickerPresentation: @MainActor () async -> Bool
    
    @State private var showPermissionPrompt = false
    @State private var isPickerPresented = false
    @State private var isCheckingAdmission = false
    @State private var admissionTask: Task<Void, Never>?
    @State private var authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    
    private var buttonContent: some View {
        ZStack {
            if isCheckingAdmission {
                ProgressView()
                    .tint(.white)
                    .accessibilityHidden(true)
            } else if let thumbnail = latestThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            } else {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .circularMaterialControl(colorScheme: .dark)
        .accessibilityIdentifier("PhotoLibraryButton")
    }
    
    var body: some View {
        Button {
            handleTap()
        } label: {
            buttonContent
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable || isCheckingAdmission)
        .padding(.leading, 32)
        .accessibilityLabel(
            isCheckingAdmission ? "Checking scan availability" : "Photo library"
        )
        .photosPicker(
            isPresented: $isPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: maxSelectionCount,
            matching: .images,
            photoLibrary: .shared()
        )
        .sheet(isPresented: $showPermissionPrompt) {
            PhotoLibraryPermissionSheetView {
                authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                showPermissionPrompt = false
            }
            .presentationDetents([.height(350)])
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            } else {
                admissionTask?.cancel()
            }
        }
        .onChange(of: isAvailable) { _, available in
            if !available {
                admissionTask?.cancel()
            }
        }
        .onDisappear {
            admissionTask?.cancel()
        }
    }

    private func handleTap() {
        guard isAvailable else { return }
        guard authStatus != .notDetermined else {
            showPermissionPrompt = true
            return
        }
        guard admissionTask == nil else { return }

        isCheckingAdmission = true
        admissionTask = Task { @MainActor in
            defer {
                isCheckingAdmission = false
                admissionTask = nil
            }

            let shouldPresentPicker = await onRequestPickerPresentation()
            guard shouldPresentPicker,
                  !Task.isCancelled,
                  scenePhase == .active else {
                return
            }
            isPickerPresented = true
        }
    }
}
