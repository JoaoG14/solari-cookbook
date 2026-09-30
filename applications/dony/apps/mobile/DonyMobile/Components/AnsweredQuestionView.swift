import SwiftUI

struct AnsweredQuestionView: View {
    let summary: SyncAnsweredQuestion
    var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(summary.header, systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if sending {
                    ProgressView("Sending…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color("TodoMuted"))
                } else {
                    Text("Answered")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color("TodoMuted"))
                }
            }
            ForEach(summary.answers.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    Text(summary.answers[index].question)
                        .font(.body.weight(.semibold))
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
                        Text(summary.answers[index].answer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("TodoInk").opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("answered-question-\(summary.id)")
    }
}
