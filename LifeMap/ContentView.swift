import SwiftUI
import SwiftData

/// The app's top-level tabs, so views can send the user to another tab.
enum AppTab: Hashable, CaseIterable, Identifiable {
    case trips
    case map
    case live
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .trips: "Trips"
        case .map: "Map"
        case .live: "Live"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .trips: "list.bullet.rectangle"
        case .map: "map"
        case .live: "dot.radiowaves.left.and.right"
        case .settings: "gear"
        }
    }
}

/// Which tab is showing and whether the tab bar should be visible. Shared through the
/// environment so any screen can switch tabs or hide the bar while it is on screen.
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .trips
    var isTabBarHidden = false
}

struct ContentView: View {
    @State private var filter = TripFilter()
    @State private var navigation = AppNavigation()

    var body: some View {
        @Bindable var navigation = navigation
        // The system tab bar is hidden in favour of `AppTabBar`, which each tab adds as a
        // bottom inset so it sits flush with the screen edge. TabView keeps tab state alive.
        TabView(selection: $navigation.selectedTab) {
            Tab(AppTab.trips.title, systemImage: AppTab.trips.symbolName, value: .trips) {
                TripListView(filter: $filter)
                    .toolbar(.hidden, for: .tabBar)
            }
            Tab(AppTab.map.title, systemImage: AppTab.map.symbolName, value: .map) {
                TripsMapView(filter: $filter)
                    .toolbar(.hidden, for: .tabBar)
            }
            Tab(AppTab.live.title, systemImage: AppTab.live.symbolName, value: .live) {
                LiveView()
                    .toolbar(.hidden, for: .tabBar)
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.symbolName, value: .settings) {
                SettingsView()
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .environment(navigation)
    }
}

extension View {
    /// Reserves space for, and shows, the app's tab bar along the bottom edge. Apply this
    /// to the root content inside each tab's `NavigationStack`; an inset applied outside the
    /// stack doesn't reach the content within it.
    func appTabBarInset() -> some View {
        modifier(AppTabBarInset())
    }
}

private struct AppTabBarInset: ViewModifier {
    @Environment(AppNavigation.self) private var navigation

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !navigation.isTabBarHidden {
                    AppTabBar()
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.snappy, value: navigation.isTabBarHidden)
    }
}

/// A tab bar that fills the width of the screen and runs to its bottom edge.
private struct AppTabBar: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = navigation.selectedTab == tab
                Button {
                    navigation.selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 22))
                            .frame(height: 26)
                        Text(tab.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(.bar)
                .overlay(alignment: .top) {
                    Divider()
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard)
    let container = try! ModelContainer(
        for: Trip.self, TrackPoint.self, ListeningEvent.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let coordinator = TrackingCoordinator(settings: settings, modelContext: container.mainContext)
    ContentView()
        .environment(settings)
        .environment(coordinator)
        .modelContainer(container)
}
