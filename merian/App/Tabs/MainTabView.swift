import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1
    @StateObject private var cameraViewModel = CameraViewModel()
    
    // Hoisted state for Views
    @State private var activeLifeListTab: LifeListTab = .library
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    @State private var showSettings = false
    
    @Namespace private var tabNamespace
    
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
                    .ignoresSafeArea()
                    .tag(1)
                
                UserProfileView(showSettings: $showSettings)
                    .environmentObject(cameraViewModel)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            
            // Navigation Pill Header
            // Liquid Glass Menu Bar style
            HStack(spacing: 4) {
                TabBarButton(title: "Scans", isSelected: selectedTab == 0, namespace: tabNamespace) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedTab = 0 }
                }
                TabBarButton(title: "Camera", isSelected: selectedTab == 1, namespace: tabNamespace) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedTab = 1 }
                }
                TabBarButton(title: "Profile", isSelected: selectedTab == 2, namespace: tabNamespace) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedTab = 2 }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            .padding(.top, 16)
        }
        .environment(\.colorScheme, .dark) // Enforce dark scheme for tabs / gradients over camera
    }
}

struct TabBarButton: View {
    let title: String
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(Color.white.opacity(0.25))
                                .matchedGeometryEffect(id: "TabBackground", in: namespace)
                        } else {
                            Capsule().fill(Color.clear)
                        }
                    }
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
