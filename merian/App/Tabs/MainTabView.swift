import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1
    @StateObject private var cameraViewModel = CameraViewModel()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LifeListSearchView(isInsightSheetOpen: $cameraViewModel.isInsightSheetOpen)
                    .environmentObject(cameraViewModel)
            }
            .tabItem {
                Label("Scans", systemImage: "book")
            }
            .tag(0)
            
            CameraRootView()
                .environmentObject(cameraViewModel)
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
                .tag(1)
            
            NavigationStack {
                UserProfileView()
                    .environmentObject(cameraViewModel)
            }
            .tabItem {
                Label("Profile", systemImage: "person")
            }
            .tag(2)
        }
        .tint(.white) 
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
    }
}
