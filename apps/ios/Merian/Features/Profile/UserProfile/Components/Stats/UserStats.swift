import SwiftUI

struct UserStats: View {
    let speciesCount: Int
    let streak: Int

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 24),
                GridItem(.flexible())
            ],
            spacing: 16
        ) {
            StatCard(
                title: "Species discovered",
                value: "\(speciesCount)",
                imageName: "leaf",
                color: .green
            )
            StatCard(
                title: "Current streak",
                value: "\(streak) day\(streak == 1 ? "" : "s")",
                imageName: "fire",
                color: .orange
            )
        }
    }
}
