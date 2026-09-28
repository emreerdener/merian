import SwiftUI
import XCTest
@testable import Merian

@MainActor
private final class AppRootAlertFixture: ObservableObject {
    @Published var showsScans = false
    @Published var request: AppRootAlert?
}

private struct AppRootAlertFixtureView: View {
    @ObservedObject var state: AppRootAlertFixture

    var body: some View {
        Text("Capture")
            .sheet(isPresented: $state.showsScans) { Text("Saved observations") }
            .modifier(AppRootAlertHost(
                request: state.request,
                openAppleInstructions: {}, resolveAppleRevocation: {}, updateApp: {},
                dismissUpdate: { state.request = nil }
            ))
    }
}

@MainActor
final class AppRootAlertHostTests: XCTestCase {
    func testUpdateAlertAppearsAboveAnExistingSheetAndLeavesItOpen() async throws {
        try await verifySheetAndAlert(simultaneous: false)
    }

    func testUpdateAlertAndNewSheetDoNotCompete() async throws {
        try await verifySheetAndAlert(simultaneous: true)
    }

    private func verifySheetAndAlert(simultaneous: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let state = AppRootAlertFixture()
        let host = UIHostingController(rootView: AppRootAlertFixtureView(state: state)
            .environment(\.scenePhase, .active))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        state.showsScans = true
        if simultaneous { state.request = .appUpdate }
        for _ in 0..<30 {
            if host.presentedViewController != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let sheet = try XCTUnwrap(host.presentedViewController)
        XCTAssertFalse(sheet is UIAlertController, "The alert must not take the sheet’s presentation slot")
        try await Task.sleep(for: .milliseconds(500))
        state.request = .appUpdate
        for _ in 0..<30 {
            if sheet.presentedViewController is UIAlertController { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let alert = try XCTUnwrap(sheet.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.title, "Update Naturebook")
        XCTAssertEqual(Set(alert.actions.compactMap(\.title)), ["Update app", "Not now"])
        state.request = nil
        for _ in 0..<30 {
            if sheet.presentedViewController == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(sheet.presentedViewController)
        XCTAssertTrue(host.presentedViewController === sheet)
        XCTAssertTrue(state.showsScans)
    }
}
