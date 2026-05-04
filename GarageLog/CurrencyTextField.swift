#if canImport(UIKit)
import SwiftUI
import UIKit

struct CurrencyTextField: UIViewRepresentable {
    @Binding var value: Double
    var isDisabled: Bool = false

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textAlignment = .right
        tf.backgroundColor = .clear
        tf.font = UIFont.preferredFont(forTextStyle: .body)
        tf.delegate = context.coordinator
        tf.text = Self.format(cents: context.coordinator.cents)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.isUserInteractionEnabled = !isDisabled
        uiView.textColor = isDisabled ? UIColor.secondaryLabel : UIColor.label
        if !context.coordinator.isEditing || isDisabled {
            context.coordinator.cents = Int((value * 100).rounded())
            uiView.text = Self.format(cents: context.coordinator.cents)
            if isDisabled { context.coordinator.isEditing = false }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    static func format(cents: Int) -> String {
        String(format: "$%d.%02d", cents / 100, cents % 100)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var value: Double
        var cents: Int
        var isEditing = false

        init(value: Binding<Double>) {
            _value = value
            cents = Int((value.wrappedValue * 100).rounded())
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isEditing = true
            cents = Int((value * 100).rounded())
            textField.text = CurrencyTextField.format(cents: cents)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isEditing = false
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty {
                cents /= 10
            } else if string.count == 1, let digit = Int(string), string.first!.isNumber {
                let newCents = cents * 10 + digit
                if newCents <= 9_999_999 { cents = newCents }
            }
            value = Double(cents) / 100.0
            textField.text = CurrencyTextField.format(cents: cents)
            return false
        }
    }
}

#else

import SwiftUI

// macOS: plain TextField with a currency formatter — no phone keyboard to work around
private let usdFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
}()

struct CurrencyTextField: View {
    @Binding var value: Double
    var isDisabled: Bool = false

    var body: some View {
        TextField("$0.00", value: $value, formatter: usdFormatter)
            .multilineTextAlignment(.trailing)
            .disabled(isDisabled)
            .foregroundStyle(isDisabled ? .secondary : .primary)
    }
}

#endif
