import SwiftUI

struct MerianActionBar: View {
    @EnvironmentObject var syncStateManager: SyncStateManager
    @Binding var isInsightSheetOpen: Bool
    
    @State private var isSpinning: Bool = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background mask protecting full-bleed camera aesthetics
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black, Color.black.opacity(0.8), Color.clear]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: 140)
            
            HStack {
                // Left Action: Open Life List
                Button(action: {
                    print("Presenting Local Life List.")
                }) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding()
                }
                
                Spacer()
                
                // Center Action: Shutter Button
                Button(action: {
                    isInsightSheetOpen = true
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 72, height: 72)
                        
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 62, height: 62)
                    }
                }
                
                Spacer()
                
                // Right Action: Ecosystem Sync Module
                Group {
                    if !syncStateManager.isSyncing {
                        Button(action: {
                            print("Presenting Global Application Settings.")
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                        }
                    } else {
                        ZStack {
                            Circle()
                                .trim(from: 0.2, to: 1.0)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 32, height: 32)
                                .rotationEffect(Angle(degrees: isSpinning ? 360 : 0))
                                .onAppear {
                                    withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                                        isSpinning = true
                                    }
                                }
                                .onDisappear {
                                    isSpinning = false
                                }
                            
                            // Displays pending batch total cleanly
                            Text("\(syncStateManager.pendingUploadCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 50, height: 50)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }
}
