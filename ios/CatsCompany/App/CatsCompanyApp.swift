import SwiftUI

@main
struct CatsCompanyApp: App {
    @StateObject private var auth = AuthManager.shared

    init() {
        configureTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            SwiftUI.Group {
                if auth.isLoggedIn {
                    MainTabView()
                        .onAppear {
                            WebSocketManager.shared.connect()
                        }
                } else {
                    LoginView()
                }
            }
            .tint(CatColor.primary)
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ChatListView()
                .tabItem {
                    Label("消息", systemImage: "bubble.left.and.bubble.right")
                }

            ContactsView()
                .tabItem {
                    Label("通讯录", systemImage: "person.2")
                }

            ProfileView()
                .tabItem {
                    Label("我", systemImage: "person.circle")
                }
        }
    }
}
