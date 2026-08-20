import SwiftUI

/// Onboarding's third step, and the same control Settings shows: when reading
/// happens, and what the reader already does that it follows.
///
/// The routine is offered as suggestions rather than asked for blank, because
/// naming your own habit cold is harder than recognising one — and "something
/// else" is there because the four are a starting point, not the list.
struct ReadingIntentionStep: View {
    @Binding var intention: ReadingIntention
    /// Onboarding shows the whole step; Settings shows it under its own header.
    var showsHeading = true

    @State private var isWritingOwn = false
    @FocusState private var writingFocused: Bool

    private var time: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = intention.hour
                components.minute = intention.minute
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                intention.hour = components.hour ?? 21
                intention.minute = components.minute ?? 0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeading {
                Text("When do you read?")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 22)
                Text("A habit sticks to one you already have. We'll nudge you then — and stay quiet on days you've already read.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .padding(.top, 8)
            }

            FlowLayout(spacing: 8) {
                ForEach(ReadingIntention.suggestedRoutines, id: \.self) { routine in
                    routineChip(routine.prefix(1).uppercased() + routine.dropFirst(),
                                isSelected: !isWritingOwn && intention.routine == routine) {
                        isWritingOwn = false
                        intention.routine = routine
                        intention.isOn = true
                    }
                }
                routineChip("Something else…", isSelected: isWritingOwn) {
                    isWritingOwn = true
                    intention.routine = ""
                    intention.isOn = true
                    writingFocused = true
                }
            }
            .padding(.top, showsHeading ? 18 : 4)

            if isWritingOwn {
                TextField("after the school run", text: Binding(
                    get: { intention.routine ?? "" },
                    set: { intention.routine = $0 }
                ))
                .focused($writingFocused)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
                .padding(.top, 10)
                .accessibilityIdentifier("customRoutineField")
            }

            DatePicker("At", selection: time, displayedComponents: .hourAndMinute)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 14)
                .accessibilityIdentifier("intentionTime")
        }
    }

    private func routineChip(_ label: String, isSelected: Bool,
                             _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? Theme.stateLearning : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("routineChip")
    }
}
