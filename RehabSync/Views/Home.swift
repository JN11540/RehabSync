import SwiftUI

// MARK: - Treatment Selection State

@Observable
final class TreatmentSelectionState {
    var userSelectedContentId: Int64? = nil
}

// MARK: - goHome Environment Key

private struct GoHomeKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var goHome: () -> Void {
        get { self[GoHomeKey.self] }
        set { self[GoHomeKey.self] = newValue }
    }
}

// MARK: - Home Tab

private enum HomeTab: CaseIterable {
    case statistic, test, setting, test1

    var title: String {
        switch self {
        case .statistic: "數據"
        case .test: "測試"
        case .setting: "設定"
        case .test1: "測試1"
        }
    }
}

struct Home: View {
    @State private var btVM = BluetoothViewModel()
    @State private var selectedTab: HomeTab = .test1

    var body: some View {
        Group {
            switch selectedTab {
            case .statistic: Statistic()
            case .test: TestPage(btVM: btVM)
            case .setting: Setting()
            case .test1: Test1()
            }
        }
        .safeAreaInset(edge: .top) {
            FloatingTabBar(selectedTab: $selectedTab)
        }
        .environment(btVM)
        .overlay {
            if btVM.isCleaningUp {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("正在刪除舊資料")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("請稍候，完成後自動關閉")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(32)
                .background(Color(red: 0.1, green: 0.25, blue: 0.4))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

// MARK: - Floating Tab Bar

private struct FloatingTabBar: View {
    @Binding var selectedTab: HomeTab

    private let tealGreen = Color(red: 0.35, green: 0.58, blue: 0.53)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 15, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 26)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedTab == tab ? tealGreen : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.2)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black, lineWidth: 3))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

#Preview {
    Home()
}
