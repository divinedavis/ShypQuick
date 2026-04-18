import SwiftUI

struct SchedulePickerSheet: View {
    let onSchedule: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date().addingTimeInterval(3600)

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("When should we pick this up?")
                    .font(.title2.bold())
                    .padding(.top)

                DatePicker(
                    "Pickup time",
                    selection: $selectedDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)

                Spacer()

                Button {
                    onSchedule(selectedDate)
                    dismiss()
                } label: {
                    Text("Schedule delivery")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
