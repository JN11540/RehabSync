import SwiftUI

// MARK: - Test1

struct Test1: View {
    private let navy = Color(red: 0.1, green: 0.25, blue: 0.4)
    private let mint = Color(red: 0.25, green: 0.85, blue: 0.75)

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 20
            let hPad: CGFloat = 24
            let usable = geo.size.width - hPad * 2 - spacing

            HStack(alignment: .top, spacing: spacing) {
                Test1Sidebar(mint: mint)
                    .frame(width: usable * 0.35)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                Test1PreviewFrame(navy: navy)
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

    var body: some View {
        VStack(spacing: 20) {
            Test1MenuTile(title: "掃描 QR code", mint: mint) {
                ColorfulQRIcon()
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
            Test1MenuTile(title: "訓練菜單", mint: mint)
            Test1MenuTile(title: "商店", mint: mint)
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

// MARK: - Colorful QR Icon

private struct ColorfulQRIcon: View {
    private let colors: [Color] = [
        .red, .white, .orange,
        .yellow, .red, .white,
        .orange, .yellow, .red
    ]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<3) { row in
                HStack(spacing: 2) {
                    ForEach(0..<3) { col in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[row * 3 + col])
                    }
                }
            }
        }
        .frame(width: 34, height: 34)
        .scaleEffect(2.2)
    }
}

// MARK: - Preview Frame

private struct Test1PreviewFrame: View {
    let navy: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(navy.opacity(0.5))
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.25), lineWidth: 3)

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
}

#Preview {
    Test1()
}
