import SwiftUI

struct ContentView: View {
    @State private var viewModel = PlannerViewModel()
    @State private var timerManager = StudyTimerManager()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(viewModel: viewModel, timerManager: timerManager)
            }
            .tabItem {
                Label("Dashboard", systemImage: "square.grid.2x2.fill")
            }

            NavigationStack {
                CalendarView(viewModel: viewModel)
            }
            .tabItem {
                Label("Calendario", systemImage: "calendar")
            }

            NavigationStack {
                SettingsView(viewModel: viewModel)
            }
            .tabItem {
                Label("Perfil", systemImage: "gearshape.fill")
            }
        }
        .onChange(of: appearance, initial: true) { _, newValue in
            AppAppearance.apply(newValue)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // El estado del timer ya se guarda en cada cambio; al volver solo hay que revisarlo
            if newPhase == .active {
                timerManager.refresh()
                AppAppearance.apply(appearance)
            }
        }
    }
}
