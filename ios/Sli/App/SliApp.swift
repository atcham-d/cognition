import SwiftUI

@main
struct SliApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { await state.load() }
        }
    }
}
