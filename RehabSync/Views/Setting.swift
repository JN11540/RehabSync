import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Result

private enum ExportResult {
    case allCompleted
    case incomplete([String])
}

// MARK: - Setting

struct Setting: View {
    @State private var vm = TreatmentViewModel()
    @State private var showFileImporter = false
    @State private var importError: String?
    @State private var importSuccess = false
    @State private var showDeleteConfirm = false
    @State private var showExportSheet = false

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

            Button("匯出治療計畫") {
                showExportSheet = true
            }
            .sheet(isPresented: $showExportSheet) {
                ExportSheet(treatments: vm.treatments)
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
        .onAppear {
            vm.fetchAll()
        }
    }
}

// MARK: - Export Sheet

private struct ExportSheet: View {
    let treatments: [Treatment]
    @State private var selectedTreatmentId: Int? = nil
    @State private var serverIP = ""
    @State private var exportResult: ExportResult? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("選擇治療計畫") {
                    if treatments.isEmpty {
                        Text("尚未匯入任何治療計畫")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("治療計畫", selection: $selectedTreatmentId) {
                            Text("請選擇").tag(Optional<Int>.none)
                            ForEach(treatments, id: \.id) { t in
                                Text(t.name).tag(Optional(Int(t.id ?? 0)))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("伺服器設定") {
                    TextField("伺服器 IP", text: $serverIP)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("確認匯出") {
                        checkCompletion()
                    }
                    .disabled(selectedTreatmentId == nil || treatments.isEmpty)
                }

                if let result = exportResult {
                    Section("結果") {
                        switch result {
                        case .allCompleted:
                            Label("治療計畫已完成", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .incomplete(let names):
                            VStack(alignment: .leading, spacing: 8) {
                                Text("尚有以下動作未完成：")
                                    .foregroundStyle(.secondary)
                                ForEach(names, id: \.self) { name in
                                    Label(name, systemImage: "xmark.circle")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("匯出治療計畫")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }

    private func checkCompletion() {
        guard let tid = selectedTreatmentId else { return }

        let contentVM = TreatmentContentViewModel()
        contentVM.fetchAll(for: tid)
        let allContents = contentVM.contents

        let resultVM = TreatmentResultViewModel()
        let completedIds = resultVM.fetchCompletedContentIds(for: tid)

        let exerciseVM = ExerciseViewModel()
        exerciseVM.fetchAll()

        let incompleteContents = allContents.filter {
            !completedIds.contains(Int($0.id ?? -1))
        }

        if incompleteContents.isEmpty && !allContents.isEmpty {
            exportResult = .allCompleted
        } else {
            let names = incompleteContents.map { content in
                exerciseVM.exercises.first { Int($0.id ?? 0) == content.exercise_id }?.name ?? "未知動作"
            }
            exportResult = .incomplete(names)
        }
    }
}

#Preview {
    Setting()
}
