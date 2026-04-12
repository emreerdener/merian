import SwiftUI

struct CandidateImageExpandedView: View {
    let images: [UIImage]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView {
                ForEach(images, id: \.self) { img in
                    ZoomableScrollView {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    }
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
