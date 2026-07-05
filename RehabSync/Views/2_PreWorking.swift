import SwiftUI

// MARK: - PreWorking2

struct PreWorking2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private var stepTitle: String {
        switch step {
        case 0: return "確認裝備齊全"
        case 1: return "準備椅子"
        default: return "校正"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.85, green: 0.93, blue: 0.98))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(white: 0.6), lineWidth: 5)
                    )
                    .overlay(alignment: .top) {
                        Text(stepTitle)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.top, 24)
                    }

                if step == 0 {
                    HStack(spacing: 24) {
                        VStack(spacing: 0) {
                            Image("Assure1Icon")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .padding(4)
                            AssureLabel(text: "裝置連線")
                                .padding(.horizontal, 4)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 0) {
                            Image("Assure2Icon")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .padding(4)
                            AssureLabel(text: "護膝穿戴")
                                .padding(.horizontal, 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 174)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if step == 1 {
                    VStack(spacing: 12) {
                        Image("ChairIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)

                        Text("請先找一張高度剛好到您膝蓋的椅子")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if step == 2 {
                    VStack(spacing: 16) {
                        Image("StopNoMoveIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)
                            .padding(.leading, 20)

                        Text("請坐在椅子上，將膝蓋保持 90 度彎曲。點擊『校正』按鈕後，請維持身體靜止不動 5 秒鐘喔！")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                            .padding(.leading, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Button(action: {}) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.99, green: 0.88, blue: 0.49))
                            Circle()
                                .strokeBorder(Color.black, lineWidth: 6)
                            Text("校正")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        .frame(width: 200, height: 200)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 40)
                }

                Button(action: { dismiss() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                        Circle()
                            .strokeBorder(Color.black, lineWidth: 1.5)
                        Circle()
                            .strokeBorder(Color.black, lineWidth: 1.5)
                            .padding(4)
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .frame(width: 40, height: 40)
                    .padding(16)
                }
                .buttonStyle(.plain)

                if step < 2 {
                    Button(action: { step += 1 }) {
                        Image("ArrowIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 0)
                }

                if step > 0 {
                    Button(action: { step -= 1 }) {
                        Image("ArrowIcon")
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(x: -1, y: 1)
                            .frame(width: 150, height: 150)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 0)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 40)
            .padding(.leading, 60)
            .padding(.trailing, 60)
        }
    }
}

// MARK: - Assure Label

private struct AssureLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.black)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    PreWorking2(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 2,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil
    )
}
