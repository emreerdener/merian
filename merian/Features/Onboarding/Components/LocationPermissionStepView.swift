import SwiftUI
import CoreLocation
import RiveRuntime

struct LocationPermissionStepView: View {
    @ObservedObject var locationManagerDelegate: LocationPermissionDelegate
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            // TODO: Drop RiveViewModel file here
            Rectangle()
                .fill(Color.green.opacity(0.1))
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
                .overlay(Text("Location Rive Animation").foregroundColor(.gray))
            
            VStack(spacing: 16) {
                Text("Where you are\nmatters")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Merian uses your geographic coordinate context to instantly improve AI accuracy and identify local ecology.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    locationManagerDelegate.onAuthorizationDetermined = {
                        onNext()
                    }
                    locationManagerDelegate.requestWhenInUse()
                } label: {
                    Text("Enable Location")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.8))
                        .clipShape(Capsule())
                }
                
                Button(action: onNext) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}
