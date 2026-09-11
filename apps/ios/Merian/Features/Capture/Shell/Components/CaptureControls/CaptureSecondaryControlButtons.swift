import SwiftUI

struct CaptureDescribeDictationButton: View {
    let isRecording: Bool
    let audioLevel: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isRecording {
                    Circle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: 50, height: 50)
                        .scaleEffect(1 + (audioLevel * 0.4))
                        .opacity(1 - (Double(audioLevel) * 0.5))
                        .animation(
                            .easeOut(duration: 0.15),
                            value: audioLevel
                        )
                }

                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(isRecording ? Color.red : Color.clear)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .environment(\.colorScheme, .dark)
                    .animation(
                        .easeInOut(duration: 0.2),
                        value: isRecording
                    )
            }
            .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 32)
        .accessibilityLabel(isRecording ? "Stop dictation" : "Start dictation")
        .accessibilityIdentifier("DescribeDictation")
    }
}

struct CaptureVideoCancelButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.red)
                .circularMaterialControl(colorScheme: .dark)
        }
        .buttonStyle(.plain)
        .padding(.leading, 32)
    }
}

struct CapturePromptListButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "list.bullet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .circularMaterialControl(colorScheme: .dark)
        }
        .buttonStyle(.plain)
        .padding(.leading, 32)
        .accessibilityLabel("Show prompts")
        .accessibilityIdentifier("DescribePrompts")
    }
}

struct CaptureAudioDeleteButton: View {
    let isRecording: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: isRecording ? "xmark" : "trash")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.red)
                .circularMaterialControl(colorScheme: .dark)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .padding(.leading, 32)
    }
}

struct CaptureAudioDoneButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Color.accentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 32)
    }
}

struct CaptureAudioReviewPlayButton: View {
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .circularMaterialControl(colorScheme: .dark)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 32)
    }
}
