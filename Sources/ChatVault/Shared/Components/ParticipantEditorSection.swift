import SwiftUI

struct ParticipantEditorSection: View {
    @Binding var participants: [ImportParticipantDraft]
    @Binding var title: String
    let fallbackTitle: String

    var body: some View {
        Section {
            ForEach($participants) { $participant in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Display name", text: $participant.displayName)
                        Toggle("Me", isOn: $participant.isMe)
                            .toggleStyle(.checkbox)
                            .onChange(of: participant.isMe) { _, isMe in
                                if isMe {
                                    for index in participants.indices where participants[index].id != participant.id {
                                        participants[index].isMe = false
                                    }
                                    updateSuggestedTitle()
                                }
                            }
                    }

                    Text("Export name: \(participant.exportName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let month = participant.birthdayMonth,
                       let day = participant.birthdayDay {
                        Label(
                            "Birthday detected: \(formattedBirthday(month: month, day: day))",
                            systemImage: "birthday.cake"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("People")
        } footer: {
            Text("Set display names to identify people in group chats. Mark yourself as \"Me\" so sent messages align correctly.")
                .font(.caption)
        }
    }

    private func updateSuggestedTitle() {
        title = ChatTitleSuggester.suggestedTitle(for: participants, fallback: fallbackTitle)
    }

    private func formattedBirthday(month: Int, day: Int) -> String {
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = 2000
        guard let date = Calendar.current.date(from: components) else { return "\(month)/\(day)" }
        return date.formatted(.dateTime.month(.wide).day())
    }
}
