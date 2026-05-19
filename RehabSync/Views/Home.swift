import SwiftUI

struct Home: View {
    var body: some View {
        TabView {
            Text("主頁")
                .tabItem {
                    Label("主頁", systemImage: "house")
                }
            Statistic()
                .tabItem {
                    Label("數據", systemImage: "chart.bar")
                }
            Setting()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    Home()
}
