import SwiftUI

struct BirthdaysTodayView: View {
    let reminders: [BirthdayReminder]
    let onSelect: (BirthdayReminder) -> Void

    var body: some View {
        if !reminders.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Birthdays Today", systemImage: "birthday.cake.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.pink)

                ForEach(reminders) { reminder in
                    Button {
                        onSelect(reminder)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.personName)
                                    .font(.subheadline.weight(.medium))
                                Text(reminder.archiveTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let note = reminder.birthdayNote {
                                    Text(note)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.pink.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}
