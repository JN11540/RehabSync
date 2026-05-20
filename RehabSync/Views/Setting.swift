import SwiftUI
import UniformTypeIdentifiers

struct Setting: View {
    @State private var showFileImporter = false
    @State private var importError: String?
    @State private var importSuccess = false

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
                        try ImportJSON.shared.importTreatment(from: url)
                        importSuccess = true
                    } catch {
                        importError = error.localizedDescription
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
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
