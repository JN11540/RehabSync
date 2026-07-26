import SwiftUI

/// 占位畫面：exercise_id 22（前跨步弓步蹲）的正式遊戲畫面尚未實作，
/// 這裡先提供跟 Working12 相同的公開介面，讓 PreWorking_22 可以編譯並串接流程。
struct Working22: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let onReturnToDashboard: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("弓步遊戲畫面開發中")
                .font(.system(size: 28, weight: .bold))

            Button("返回") {
                onReturnToDashboard()
                dismiss()
            }
            .font(.system(size: 20, weight: .semibold))
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Color(red: 0.45, green: 0.35, blue: 0.85))
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea()
    }
}
