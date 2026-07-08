import SwiftUI

// MARK: - PostWorking2

struct PostWorking2: View {
    let content: TreatmentContent
    let exercise: Exercise?

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.85, green: 0.93, blue: 0.98))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(white: 0.6), lineWidth: 5)
                    )

                VStack {
                    HStack(alignment: .bottom, spacing: 60) {
                        Image("FinishGameLeftIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)

                        Image("FinishGameRightIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 1.0, green: 0.85, blue: 0.35))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.70, green: 0.52, blue: 0.10), lineWidth: 3)
                                    )
                                Image("CoinIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                    .padding(8)
                                    .offset(x: -10, y: -30)
                                VStack(spacing: 2) {
                                    Text("0")
                                        .font(.system(size: 30, weight: .bold))
                                    Text("金幣")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(8)
                            }

                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.75, green: 0.90, blue: 0.98))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.314, green: 0.647, blue: 0.863), lineWidth: 3)
                                    )
                                Image("RepsIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .offset(x: -45, y: -20)
                                VStack(spacing: 2) {
                                    Text("0")
                                        .font(.system(size: 30, weight: .bold))
                                    Text("總次數")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(8)
                            }

                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.85, green: 0.96, blue: 0.99))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.490, green: 0.824, blue: 0.937), lineWidth: 3)
                                    )
                                Image("TotalTimeIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                                    .offset(x: -10, y: -10)
                                VStack(spacing: 2) {
                                    Text("0")
                                        .font(.system(size: 30, weight: .bold))
                                    Text("總時長")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(8)
                            }

                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.88, green: 0.93, blue: 0.95))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.678, green: 0.776, blue: 0.804), lineWidth: 3)
                                    )
                                Image("BigFishIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                                    .offset(y: -20)
                                VStack(spacing: 2) {
                                    Text("0")
                                        .font(.system(size: 30, weight: .bold))
                                    Text("個")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(8)
                            }

                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.99, green: 0.93, blue: 0.75))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.992, green: 0.827, blue: 0.427), lineWidth: 3)
                                    )
                                Image("MiddleFishIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                                    .offset(y: -20)
                                VStack(spacing: 2) {
                                    Text("0")
                                        .font(.system(size: 30, weight: .bold))
                                    Text("個")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(8)
                            }

                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.98, green: 0.90, blue: 0.92))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.949, green: 0.773, blue: 0.800), lineWidth: 3)
                                    )
                                Image("SmallFishIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                                    .offset(y: -20)
                                VStack(spacing: 2) {
                                    Text("0")
                                        .font(.system(size: 30, weight: .bold))
                                    Text("個")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                                .foregroundStyle(Color.black)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                    .padding(8)
                            }
                        }
                        .frame(height: 100)

                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 1.0, green: 0.96, blue: 0.85))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.70, green: 0.52, blue: 0.10), lineWidth: 3)
                                    )

                                VStack(spacing: 0) {
                                    Spacer()
                                    HStack(alignment: .bottom, spacing: 16) {
                                        VStack(spacing: 4) {
                                            Text("0")
                                                .font(.system(size: 30, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.70, green: 0.52, blue: 0.10))
                                            Rectangle()
                                                .fill(Color(red: 1.0, green: 0.85, blue: 0.60))
                                                .frame(width: 200, height: 60)
                                        }
                                        VStack(spacing: 4) {
                                            Text("1000")
                                                .font(.system(size: 30, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.70, green: 0.52, blue: 0.10))
                                            Rectangle()
                                                .fill(Color(red: 1.0, green: 0.70, blue: 0.25))
                                                .frame(width: 200, height: 110)
                                        }
                                    }
                                    Rectangle()
                                        .fill(Color(red: 0.70, green: 0.52, blue: 0.10))
                                        .frame(height: 2)
                                    HStack(spacing: 16) {
                                        Text("2026/07/07 15:00")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.70, green: 0.52, blue: 0.10))
                                            .frame(width: 200)
                                        Text("2026/07/07 17:00")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.70, green: 0.52, blue: 0.10))
                                            .frame(width: 200)
                                    }
                                }
                                .padding(16)

                                Image("CoinIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                            }
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.6), lineWidth: 1.5))
                        }
                        .frame(height: 200)

                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.6), lineWidth: 1.5))
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.6), lineWidth: 1.5))
                        }
                        .frame(height: 200)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 0)
                    .offset(y: -20)

                    Spacer()
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 40)
            .padding(.leading, 60)
            .padding(.trailing, 60)
        }
    }
}

#Preview {
    PostWorking2(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 2,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil
    )
}
