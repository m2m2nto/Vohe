import SwiftUI
import UIKit

struct MinuteIntervalDatePicker: UIViewRepresentable {
    @Binding var date: Date
    var minuteInterval: Int = 5

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.minuteInterval = minuteInterval
        picker.preferredDatePickerStyle = .compact
        picker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.changed(_:)),
            for: .valueChanged
        )
        picker.date = date
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        if picker.minuteInterval != minuteInterval { picker.minuteInterval = minuteInterval }
        if abs(picker.date.timeIntervalSince(date)) > 0.5 { picker.date = date }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        let fitting = uiView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(
            width: fitting.width > 0 ? fitting.width : 110,
            height: max(fitting.height, 34)
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: MinuteIntervalDatePicker
        init(_ parent: MinuteIntervalDatePicker) { self.parent = parent }
        @objc func changed(_ picker: UIDatePicker) { parent.date = picker.date }
    }
}
