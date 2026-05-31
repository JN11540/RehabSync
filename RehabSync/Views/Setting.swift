import SwiftUI

// MARK: - Export Enums

private enum ExportResult {
    case allCompleted
    case incomplete([String])
}

private enum UploadStatus {
    case uploading
    case success
    case failure(String)
}

// MARK: - Setting

struct Setting: View {
    @State private var vm = TreatmentViewModel()
    @State private var showDeleteConfirm = false
    @State private var showExportSheet = false
    @State private var showQRScanner = false
    @State private var qrSuccess = false
    @State private var qrError: String?

    private let iconBg = Color(red: 0.1, green: 0.25, blue: 0.4)

    var body: some View {
        List {
            Section("其他設定") {
                SettingRow(icon: "qrcode", iconBg: iconBg, title: "掃描 QR Code") {
                    qrSuccess = false
                    qrError = nil
                    showQRScanner = true
                }

                SettingRow(icon: "square.and.arrow.up.fill", iconBg: iconBg, title: "匯出治療計畫") {
                    showExportSheet = true
                }

                SettingRow(icon: "trash.fill", iconBg: Color(red: 0.75, green: 0.15, blue: 0.15),
                           title: "移除所有資料", titleColor: .red) {
                    showDeleteConfirm = true
                }
            }

            if qrSuccess || qrError != nil {
                Section {
                    if qrSuccess {
                        Label("QR Code 匯入成功", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    if let err = qrError {
                        Label("QR Code 匯入失敗：\(err)", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showQRScanner) {
            QRScannerView { scannedStr in
                do {
                    try vm.importFromQRCode(scannedStr)
                    qrSuccess = true
                } catch {
                    qrError = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(treatments: vm.treatments)
        }
        .confirmationDialog("確定要移除所有資料？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("移除所有資料", role: .destructive) { vm.deleteAll() }
            Button("取消", role: .cancel) {}
        }
        .onAppear { vm.fetchAll() }
    }
}

// MARK: - Setting Row

private struct SettingRow: View {
    let icon: String
    let iconBg: Color
    let title: String
    var titleColor: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconBg)
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .foregroundStyle(titleColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
    }
}

// MARK: - Export Sheet

private struct ExportSheet: View {
    let treatments: [Treatment]
    @State private var resultVM = TreatmentResultViewModel()
    @State private var selectedTreatmentId: Int? = nil
    @State private var exportResult: ExportResult? = nil
    @State private var uploadStatus: UploadStatus? = nil
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

                Section {
                    Button("確認匯出") {
                        Task { await confirm() }
                    }
                    .disabled(selectedTreatmentId == nil || treatments.isEmpty)
                }

                if let result = exportResult {
                    Section("完成狀態") {
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

                if let status = uploadStatus {
                    Section("上傳狀態") {
                        switch status {
                        case .uploading:
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("上傳中...")
                                    .foregroundStyle(.secondary)
                            }
                        case .success:
                            Label("上傳成功", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label("上傳失敗：\(msg)", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
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

    private func confirm() async {
        guard let tid = selectedTreatmentId else { return }

        // Step 1: 本機完成狀態查詢
        let contentVM = TreatmentContentViewModel()
        contentVM.fetchAll(for: tid)
        let allContents = contentVM.contents

        resultVM.fetchAll(for: tid)
        let completedIds = Set(resultVM.results.map { $0.treatment_content_id })

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

        // Step 2: 建立 POST payload
        let payload = TreatmentReportPayload(
            treatment_id: tid,
            contents: resultVM.results.map {
                TreatmentResultItem(
                    treatment_content_id: $0.treatment_content_id,
                    reps: $0.reps,
                    total_time: $0.total_time,
                    date: $0.date
                )
            }
        )

        // Step 3: POST
        uploadStatus = .uploading
        do {
            try await resultVM.postReport(payload: payload)
            uploadStatus = .success
        } catch {
            uploadStatus = .failure(error.localizedDescription)
        }
    }
}

#Preview {
    Setting()
}
