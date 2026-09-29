import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        TabView {
            NavigationView { ItemListView() }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("库存", systemImage: "shippingbox") }

            NavigationView { BusinessView() }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("生意", systemImage: "chart.bar") }

            NavigationView { ContactListView() }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("往来", systemImage: "person.2") }

            NavigationView { SettingsView() }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .alert(isPresented: showsError) {
            Alert(title: Text("出错了"),
                  message: Text(store.errorMessage ?? ""),
                  dismissButton: .default(Text("知道了")))
        }
    }

    private var showsError: Binding<Bool> {
        Binding(get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })
    }
}
