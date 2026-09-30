import SwiftUI

struct TodoDatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var date: Date
    let save: (String?) -> Void

    init(dueDate: String?, save: @escaping (String?) -> Void) {
        self._date = State(initialValue: dueDate.map { TodoDueDate.date($0) } ?? .now)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 8)
                    choice("Today", icon: "calendar", days: 0, color: .green)
                    choice("Tomorrow", icon: "sun.max", days: 1, color: .orange)
                    choice("Next week", icon: "calendar.badge.clock", days: 7, color: .purple)
                    Button {
                        save(nil)
                        dismiss()
                    } label: {
                        Label("No date", systemImage: "circle.slash")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .foregroundStyle(Color("TodoMuted"))
                    }
                    Divider().padding(.vertical, 8)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("due-date-picker")
                }
                .padding(20)
            }
            .background(Color("TodoSurface"))
            .navigationTitle("Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        save(TodoDueDate.key(date))
                        dismiss()
                    }
                }
            }
            .labelStyle(.titleAndIcon)
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
    }

    private func choice(_ title: String, icon: String, days: Int, color: Color) -> some View {
        let selected = Calendar.current.date(byAdding: .day, value: days, to: .now)!
        return Button {
            save(TodoDueDate.key(selected))
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(title).foregroundStyle(Color("TodoInk"))
                Spacer()
                Text(selected.formatted(.dateTime.weekday(.abbreviated)))
                    .foregroundStyle(Color("TodoMuted"))
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel(title)
        .accessibilityValue(selected.formatted(date: .complete, time: .omitted))
    }
}
