import SwiftUI

struct DateJumpView: View {
    let days: [MessageDaySummary]
    let onSelectDay: (MessageDaySummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMonth: Date
    @State private var viewMode: ViewMode = .calendar

    private enum ViewMode: String, CaseIterable, Identifiable {
        case calendar = "Calendar"
        case timeline = "Timeline"

        var id: String { rawValue }
    }

    init(days: [MessageDaySummary], onSelectDay: @escaping (MessageDaySummary) -> Void) {
        self.days = days
        self.onSelectDay = onSelectDay
        _selectedMonth = State(initialValue: days.last?.date ?? Date())
    }

    private var daysByKey: [String: MessageDaySummary] {
        Dictionary(uniqueKeysWithValues: days.map { (MessageDaySummary.dayKey(for: $0.date), $0) })
    }

    private var monthSections: [(month: Date, days: [MessageDaySummary])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: days) { day in
            calendar.date(from: calendar.dateComponents([.year, .month], from: day.date)) ?? day.date
        }
        return grouped.keys.sorted().map { month in
            (month, grouped[month]!.sorted { $0.date < $1.date })
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if days.isEmpty {
                    EmptyStateView(
                        symbol: "calendar",
                        title: "No Dated Messages",
                        message: "This archive has no messages with timestamps to navigate."
                    )
                } else {
                    switch viewMode {
                    case .calendar:
                        calendarView
                    case .timeline:
                        timelineView
                    }
                }
            }
            .navigationTitle("Jump to Date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    private var calendarView: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                } label: {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                Text(selectedMonth, format: .dateTime.month(.wide).year())
                    .font(.headline)

                Spacer()

                Button {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal)

            let gridDays = daysInMonthGrid(for: selectedMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(for: day)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var timelineView: some View {
        List {
            ForEach(monthSections, id: \.month) { section in
                Section(section.month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(section.days) { day in
                        Button {
                            onSelectDay(day)
                            dismiss()
                        } label: {
                            HStack {
                                Text(day.date, format: .dateTime.weekday(.wide).month().day())
                                Spacer()
                                Text("\(day.messageCount) messages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let key = MessageDaySummary.dayKey(for: date)
        if let summary = daysByKey[key] {
            Button {
                onSelectDay(summary)
                dismiss()
            } label: {
                VStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.subheadline.weight(.medium))
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("\(summary.messageCount) messages")
        } else {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
    }

    private func daysInMonthGrid(for month: Date) -> [Date?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7

        var result: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                result.append(date)
            }
        }
        return result
    }
}
