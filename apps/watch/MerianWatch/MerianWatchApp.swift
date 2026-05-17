import SwiftUI

@main
struct MerianWatchApp: App {
    @StateObject private var acousticManager = WatchAcousticManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(acousticManager)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var acousticManager: WatchAcousticManager

    var body: some View {
        VStack {
            if acousticManager.isRecording {
                Text("Recording...")
                    .foregroundColor(.red)
            } else if acousticManager.isProcessing {
                Text("Processing...")
                    .foregroundColor(.orange)
            } else {
                Text("Tap to Record")
            }
            
            Button("Capture Acoustics") {
                acousticManager.startAcousticCapture()
            }
            .padding()
        }
    }
}
