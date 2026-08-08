import SwiftUI

@main
struct LiDARMeasureApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var viewModel = MeasureViewModel()

    var body: some View {
        TabView {
            MeasureView(viewModel: viewModel)
                .tabItem { Label("测量", systemImage: "ruler") }
            HistoryView(viewModel: viewModel)
                .tabItem { Label("历史", systemImage: "clock") }
            SettingsView(viewModel: viewModel)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(.cyan)
    }
}
