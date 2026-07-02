import SwiftUI

struct CandidateImageExpandedView: View {
    let images: [UIImage]
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(images, id: \.self) { img in
                        ZoomableScrollView {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                        }
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(
                get: { selectedImage ?? images.first },
                set: { selectedImage = $0 }
            ))
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                if images.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(images, id: \.self) { img in
                            Circle()
                                .fill(img == (selectedImage ?? images.first) ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            
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
