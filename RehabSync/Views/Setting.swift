import SwiftUI
import UniformTypeIdentifiers

struct Setting: View {
    @State private var vm = TreatmentViewModel()
    @State private var showFileImporter = false
    @State private var importError: String?
    @State private var importSuccess = false
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 20) {
            Button("匯入治療計畫（JSON）") {
                importSuccess = false
                importError = nil
                showFileImporter = true
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url):
                    do {
                        try vm.importTreatment(from: url)
                        importSuccess = true
                    } catch {
                        importError = error.localizedDescription
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }

            Button("移除所有資料") {
                showDeleteConfirm = true
            }
            .foregroundStyle(.red)
            .confirmationDialog("確定要移除所有資料？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("移除所有資料", role: .destructive) {
                    vm.deleteAll()
                }
                Button("取消", role: .cancel) {}
            }

            if importSuccess {
                Text("匯入成功")
                    .foregroundStyle(.green)
            }
            if let err = importError {
                Text("匯入失敗：\(err)")
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }
}

#Preview {
    Setting()
}
