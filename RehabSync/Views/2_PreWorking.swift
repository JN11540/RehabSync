import SwiftUI

// MARK: - PreWorking2

struct PreWorking2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(\.dismiss) private var dismiss
    @State private var showAssureStep = true

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
                        Text(showAssureStep ? "確認裝備齊全" : "準備椅子")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.top, 24)
                    }

                if showAssureStep {
                    VStack(spacing: 12) {
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
                    .padding(.top, 80)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                } else {
                    VStack(spacing: 12) {
                        Image("ChairIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)

                        Text("請先找一張高度剛好到您膝蓋的椅子")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.black)
                    }
                    .padding(.top, 80)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                Button(action: { showAssureStep = false }) {
                    Image("ArrowIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 0)

                if !showAssureStep {
                    Button(action: { showAssureStep = true }) {
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
            .padding(.trailing, 400)
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
