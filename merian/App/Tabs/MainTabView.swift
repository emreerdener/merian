import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1
    @StateObject private var cameraViewModel = CameraViewModel()
    
    // Hoisted state for Views
    @State private var activeLifeListTab: LifeListTab = .library
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    @State private var showSettings = false
    
    var body: some View {
        ZStack(alignment: .top) {
            
            // Swipeable Pages
            TabView(selection: $selectedTab) {
                LifeListSearchView(
                    isInsightSheetOpen: $cameraViewModel.isInsightSheetOpen,
                    activeTab: $activeLifeListTab,
                    showNewCollectionAlert: $showNewCollectionAlert,
                    newCollectionName: $newCollectionName
                )
                .environmentObject(cameraViewModel)
                .tag(0)
                
                CameraRootView()
                    .environmentObject(cameraViewModel)
                    .tag(1)
                
                UserProfileView(showSettings: $showSettings)
                    .environmentObject(cameraViewModel)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            
            // Navigation Pill Header
            // Dashboard | Transactions | Categories style
            HStack(spacing: 24) {
                TabBarButton(title: "Scans", isSelected: selectedTab == 0) {
                    withAnimation { selectedTab = 0 }
                }
                TabBarButton(title: "Camera", isSelected: selectedTab == 1) {
                    withAnimation { selectedTab = 1 }
                }
                TabBarButton(title: "Profile", isSelected: selectedTab == 2) {
                    withAnimation { selectedTab = 2 }
                }
            }
            .padding(.bottom, 8)
            .padding(.top, 8) // Optional top padding
            .background(
                LinearGradient(colors: [Color.black.opacity(0.85), Color.black.opacity(0.5), Color.clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            )
        }
        .environment(\.colorScheme, .dark) // Enforce dark scheme for tabs / gradients over camera
    }
}

struct TabBarButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                
                // Optional selection underline instead of pill background (like Copilot Categories selection)
                if isSelected {
                    Capsule()
                        .fill(Color.white)
                        .frame(height: 3)
                        .matchedGeometryEffect(id: "TabUnderline", in: namespace)
                } else {
                    Capsule()
                        .fill(Color.clear)
                        .frame(height: 3)
                }
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }
    @Namespace private var namespace
}
