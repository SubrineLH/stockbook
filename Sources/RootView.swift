import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: Store

    private var showsError: Binding<Bool> {
        Binding(get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })
    }

    var body: some View {
        TabView {
            NavigationView { ItemListView() }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("库存", systemImage: "shippingbox") }

            NavigationView { LogsView() }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("流水", systemImage: "list.bullet.rectangle") }

            NavigationView { SettingsView() }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .alert("出错了",
               isPresented: showsError,
               actions: { Button("知道了", role: .cancel) { } },
               message: { Text(store.errorMessage ?? "") })
    }
}
