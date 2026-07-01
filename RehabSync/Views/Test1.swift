import SwiftUI

// MARK: - Test1

struct Test1: View {
    private let navy = Color(red: 0.1, green: 0.25, blue: 0.4)
    private let mint = Color(red: 0.15, green: 0.6, blue: 0.55)

    var body: some View {
        ZStack {
            Image("Test1Preview")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .clipped()
            GeometryReader { geo in
                let spacing: CGFloat = 20
                let hPad: CGFloat = 24
                let usable = geo.size.width - hPad * 2 - spacing

                HStack(alignment: .top, spacing: spacing) {
                    Test1Sidebar(navy: navy, mint: mint)
                        .frame(width: usable * 0.35)
                        .frame(maxHeight: .infinity)

                    Test1PreviewFrame(navy: navy)
                        .frame(width: usable * 0.65)
                        .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, 20)
            }
        }
    }
}

// MARK: - Sidebar

private struct Test1Sidebar: View {
    let navy: Color
    let mint: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            navy
            VStack(alignment: .leading, spacing: 24) {
                Text("測試1")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                VStack(spacing: 14) {
                    Test1MenuTile(icon: "figure.walk", title: "動作", mint: mint)
                    Test1MenuTile(icon: "square.stack.3d.up", title: "模型", mint: mint)
                    Test1MenuTile(icon: "star", title: "收藏", mint: mint)
                }

                Divider().background(.white.opacity(0.2))

                VStack(spacing: 0) {
                    Test1ListRow(icon: "bell", title: "通知")
                    Test1ListRow(icon: "person.crop.circle", title: "帳戶")
                    Test1ListRow(icon: "gearshape", title: "設定")
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct Test1MenuTile: View {
    let icon: String
    let title: String
    let mint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(mint)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct Test1ListRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 22)
            Text(title)
                .font(.system(size: 15))
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.vertical, 10)
    }
}

// MARK: - Preview Frame

private struct Test1PreviewFrame: View {
    let navy: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(navy.opacity(0.9))
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
