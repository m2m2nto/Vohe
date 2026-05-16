import SwiftUI

struct ResultsView: View {
    let total: Int
    let correct: Int
    let onDone: () -> Void

    private var percent: Int {
        guard total > 0 else { return 0 }
        return Int((Double(correct) / Double(total) * 100).rounded())
    }

    private var headline: String {
        switch percent {
        case 100: return "Perfect!"
        case 80...: return "Great work"
        case 60...: return "Keep going"
        default: return "Practice makes perfect"
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: percent >= 80 ? "star.fill" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(percent >= 80 ? .yellow : .green)
            Text(headline)
                .font(.largeTitle.bold())
            Text("\(correct) / \(total)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("\(percent)% correct")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}
