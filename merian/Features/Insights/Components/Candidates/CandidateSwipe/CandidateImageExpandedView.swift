import SwiftUI

struct CandidateImageExpandedView: View {
    let images: [UIImage]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $selectedIndex) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, img in
                    ZoomableScrollView {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                     Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .padding()
                }
                Spacer()
            }
        }
    }
}
