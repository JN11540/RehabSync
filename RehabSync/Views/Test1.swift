import SwiftUI

// MARK: - Test1

struct Test1: View {
    private let navy = Color(red: 0.1, green: 0.25, blue: 0.4)
    private let mint = Color(red: 0.25, green: 0.85, blue: 0.75)
    @State private var showTrainingImages = false

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 20
            let hPad: CGFloat = 24
            let usable = geo.size.width - hPad * 2 - spacing

            HStack(alignment: .top, spacing: spacing) {
                Test1Sidebar(mint: mint) {
                    showTrainingImages = true
                }
                .frame(width: usable * 0.35)
                .frame(maxHeight: .infinity, alignment: .bottom)

                Test1PreviewFrame(navy: navy, mint: mint, showTrainingImages: showTrainingImages)
                    .frame(width: usable * 0.65)
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            Image("Test1Preview")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .clipped()
        }
    }
}

// MARK: - Sidebar

private struct Test1Sidebar: View {
    let mint: Color
    let onTrainingMenuTap: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Test1MenuTile(title: "掃描 QR code", mint: mint) {
                Image("PhoneQRIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .scaleEffect(2.8)
            }
            Test1MenuTile(title: "裝置連線", mint: mint) {
                ZStack(alignment: .topTrailing) {
                    Image("KneePadIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.9))
                        .offset(x: 8, y: 0)
                }
                .scaleEffect(2.8)
            }
            Button(action: onTrainingMenuTap) {
                Test1MenuTile(title: "訓練菜單", mint: mint) {
                    Image("MenuIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .scaleEffect(2.2)
                }
            }
            .buttonStyle(.plain)
            Test1MenuTile(title: "商店", mint: mint) {
                Image("StoreIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .scaleEffect(2.2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.75), radius: 16, y: 7)
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.black, lineWidth: 6)
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(white: 0.55), Color(white: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 18
                    )
                    .padding(3)
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.black, lineWidth: 6)
                    .padding(21)
            }
        )
    }
}

private struct Test1MenuTile<Icon: View>: View {
    let title: String
    let mint: Color
    @ViewBuilder var icon: () -> Icon

    init(title: String, mint: Color, @ViewBuilder icon: @escaping () -> Icon = { EmptyView() }) {
        self.title = title
        self.mint = mint
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 10) {
            icon()
                .padding(.leading, 14)
            Spacer()
            Text(title)
                .font(.system(size: 22, weight: .semibold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 16)
        .padding(.vertical, 30)
        .background(mint)
        .overlay(alignment: .center) {
            HStack(spacing: 14) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 200)
                    .rotationEffect(.degrees(20))
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 20, height: 200)
                    .rotationEffect(.degrees(20))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview Frame

private struct Test1PreviewFrame: View {
    let navy: Color
    let mint: Color
    var showTrainingImages: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(navy.opacity(0.5))

            if showTrainingImages {
                HStack(spacing: 16) {
                    VStack(spacing: 0) {
                        TrainingImageFrame(imageName: "TerminalKneeExtensionIcon")
                        TrainingActionPill(title: "膝關節終端伸展", mint: mint)
                    }
                    VStack(spacing: 0) {
                        TrainingImageFrame(imageName: "PartialSquatIcon")
                        TrainingActionPill(title: "部分蹲", mint: mint)
                    }
                    VStack(spacing: 0) {
                        TrainingImageFrame(imageName: "StepTrainingIcon")
                        TrainingActionPill(title: "登階運動", mint: mint)
                    }
                }
                .padding(40)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("預覽區")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.black, lineWidth: 6)
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(white: 0.55), Color(white: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 25
                    )
                    .padding(3)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.black, lineWidth: 6)
                    .padding(28)
            }
        )
    }
}

// MARK: - Training Image Frame

private struct TrainingImageFrame: View {
    let imageName: String

    /// 統一以 terminal_knee_extension_nobg.png 的原始尺寸（1651 x 1886）為外框比例基準
    private static let referenceAspectRatio: CGFloat = 1651.0 / 1886.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            Image(imageName)
                .resizable()
                .scaledToFit()
                .padding(8)
        }
        .aspectRatio(Self.referenceAspectRatio, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black, lineWidth: 4)
        )
    }
}

// MARK: - Training Action Pill

private struct TrainingActionPill: View {
    let title: String
    let mint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(mint)
            .overlay(alignment: .center) {
                HStack(spacing: 14) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 36, height: 200)
                        .rotationEffect(.degrees(20))
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 20, height: 200)
                        .rotationEffect(.degrees(20))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    Test1()
}
