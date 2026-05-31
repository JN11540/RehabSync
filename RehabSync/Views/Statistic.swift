import SwiftUI

struct Statistic: View {
    @State private var showAlert = false

    var body: some View {
        Color(red: 0.96, green: 0.94, blue: 0.91)
            .ignoresSafeArea()
            .onAppear { showAlert = true }
            .alert("目前開發中", isPresented: $showAlert) {
                Button("確定", role: .cancel) {}
            } message: {
                Text("數據功能即將推出，敬請期待。")
            }
    }
}

#Preview {
    Statistic()
}
