import SwiftUI
import Charts
import SwiftData

struct StatsDashboardView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsQuery: [AppSettings]
    @State private var vm: StatsViewModel?

    var body: some View {
        Group {
            if let vm {
                dashboardContent(vm: vm)
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Statistics")
        .onAppear { setupVM() }
    }

    private func setupVM() {
        guard vm == nil else { return }
        let settings = AppSettings.fetchOrCreate(in: modelContext)
        let newVM = StatsViewModel(modelContext: modelContext, settings: settings)
        vm = newVM
        Task { await newVM.refresh() }
    }

    @ViewBuilder
    private func dashboardContent(vm: StatsViewModel) -> some View {
        if vm.isLoading {
            ProgressView("Loading stats…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snap = vm.snapshot {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Top-level number cards
                    overviewGrid(snap)

                    // Bar chart — reviews per day
                    reviewBarChart(snap)

                    // Activity heatmap
                    activityHeatmap(snap)
                }
                .padding(24)
            }
        } else {
            ContentUnavailableView("No Data Yet", systemImage: "chart.bar", description: Text("Start studying to see your statistics."))
        }
    }

    // MARK: - Overview grid

    private func overviewGrid(_ snap: StatsSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(title: "Due Today",        value: "\(snap.dueToday)",                  icon: "clock.fill",         color: snap.dueToday > 0 ? .orange : .green)
            StatCard(title: "Retention (30d)",  value: pct(snap.retentionRate),             icon: "brain.fill",         color: .purple)
            StatCard(title: "Study Streak",     value: "\(snap.currentStreak)d",            icon: "flame.fill",         color: .red)
            StatCard(title: "Total Cards",      value: "\(snap.totalCards)",                icon: "rectangle.stack",    color: .blue)
            StatCard(title: "Total Reviews",    value: "\(snap.totalReviewed)",             icon: "checkmark.circle",   color: .teal)
            StatCard(title: "New Remaining",    value: "\(snap.newCardsTodayRemaining)",    icon: "sparkles",           color: .indigo)
        }
    }

    // MARK: - Bar chart

    private func reviewBarChart(_ snap: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviews — Last 30 Days")
                .font(.headline)

            Chart(snap.reviewsByDay) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Reviews", day.reviewed)
                )
                .foregroundStyle(Color.accentColor.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 180)
        }
        .padding(20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Heatmap

    private func activityHeatmap(_ snap: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity — Last Year")
                .font(.headline)

            let maxReviews = snap.activityByDay.map(\.reviewed).max() ?? 1
            let weeks = stride(from: 0, to: snap.activityByDay.count, by: 7).map {
                Array(snap.activityByDay[$0..<min($0 + 7, snap.activityByDay.count)])
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(weeks, id: \.first?.id) { week in
                        VStack(spacing: 3) {
                            ForEach(week) { day in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(heatColor(for: day.reviewed, max: maxReviews))
                                    .frame(width: 12, height: 12)
                                    .help("\(day.date.formatted(.dateTime.month().day())): \(day.reviewed) reviews")
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func heatColor(for count: Int, max: Int) -> Color {
        guard max > 0, count > 0 else { return Color.secondary.opacity(0.15) }
        let intensity = Double(count) / Double(max)
        return Color.accentColor.opacity(0.2 + intensity * 0.8)
    }

    private func pct(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
