import SwiftUI

struct Home: View {
    var body: some View {
        TabView {
            HomeContent()
                .tabItem { Label("主頁", systemImage: "house") }
            Statistic()
                .tabItem { Label("數據", systemImage: "chart.bar") }
            Setting()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}

// MARK: - Home Content

struct HomeContent: View {
    @State private var vm = TreatmentViewModel()

    var body: some View {
        NavigationStack {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                HomeHeader()
                    .padding(.horizontal, 24)
                GeometryReader { geo in
                    let spacing: CGFloat = 20
                    let hPad: CGFloat = 24
                    let usable = geo.size.width - hPad * 2 - spacing
                    HStack(alignment: .top, spacing: spacing) {
                        // 左欄 60%
                        TreatmentPlanSection(vm: vm)
                            .frame(width: usable * 0.6)
                            .frame(maxHeight: .infinity, alignment: .top)

                        // 右欄 40%
                        GeometryReader { rightGeo in
                            VStack(spacing: 16) {
                                HealthTipCard()
                                    .frame(height: (rightGeo.size.height - 16) * 0.6)
                                AssessmentEntryCard()
                                    .frame(height: (rightGeo.size.height - 16) * 0.4)
                            }
                        }
                        .frame(width: usable * 0.4)
                        .frame(maxHeight: .infinity)
                    }
                    .padding(.horizontal, hPad)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .onAppear { vm.fetchAll() }
        } // NavigationStack
    }
}

// MARK: - Header

struct HomeHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("Rehab")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                Text("Sync")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
            }
            Text("MOTION-SYNCHRONIZED NEUROMUSCULAR TRAINING SYSTEM")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .kerning(0.5)
        }
    }
}

// MARK: - Treatment Plan Section

struct TreatmentPlanSection: View {
    let vm: TreatmentViewModel

    var body: some View {
        let plans = vm.treatments

        if plans.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.gray.opacity(0.4))
                Text("目前沒有治療計畫")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        } else if plans.count == 1 {
            TreatmentPlanCard(treatment: plans[0])
                .frame(maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let cardHeight = geo.size.height
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(plans, id: \.id) { plan in
                            TreatmentPlanCard(treatment: plan)
                                .frame(height: cardHeight)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Treatment Plan Card

struct TreatmentPlanCard: View {
    let treatment: Treatment
    @State private var contentVM = TreatmentContentViewModel()
    @State private var resultVM = TreatmentResultViewModel()
    @State private var progress: Double = 0

    private var startDate: String {
        Date(timeIntervalSince1970: TimeInterval(treatment.start_time))
            .formatted(.dateTime.year().month().day())
    }

    private var endDate: String {
        Date(timeIntervalSince1970: TimeInterval(treatment.end_time))
            .formatted(.dateTime.year().month().day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
                Text("治療計畫")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
            }

            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.78, green: 0.88, blue: 0.95))
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(treatment.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                Text("\(startDate) ～ \(endDate)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                OutlineButton(title: "Start") {}
                NavigationLink {
                    TreatmentView(treatment: treatment)
                } label: {
                    Text("動作列表")
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                }
                Spacer()
                ProgressView(value: progress)
                    .tint(Color(red: 0.15, green: 0.6, blue: 0.55))
                    .frame(width: 100)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .onAppear {
            let tid = Int(treatment.id ?? 0)
            contentVM.fetchAll(for: tid)
            let completed = resultVM.fetchCompletedContentIds(for: tid)
            let total = contentVM.contents.count
            progress = total > 0 ? Double(completed.count) / Double(total) : 0
        }
    }
}

// MARK: - Health Tip Card

struct HealthTipCard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.1, green: 0.25, blue: 0.4)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(.green)
                    Text("今日健康提示")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("定期伸展胸肌有助於預防圓肩姿勢，減輕頸部長期負擔。")
                    .font(.system(size: 18, weight: .bold))
                    .italic()
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Assessment Entry Card

struct AssessmentEntryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 25))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
                Text("主觀量表")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
            }
            Text("記錄今日訓練前的主觀感受")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Spacer()
            Button("記錄今日評量") {}
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white)
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.25)))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - Shared Components

struct OutlineButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 16, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.white)
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
    }
}

#Preview {
    Home()
}
