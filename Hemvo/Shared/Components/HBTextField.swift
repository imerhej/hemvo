//  HBTextField.swift
//  Hemvo
//  Branded text field components used in auth and forms.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import Foundation
internal import Combine
internal import UserNotifications

// MARK: - HBTextField
struct HBTextField: View {
    let label: String
    @Binding var text: String
    var icon: String?            = nil
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool           = false
    var autocap: TextInputAutocapitalization = .never
    var submitLabelType: SubmitLabel         = .next
    var onSubmitAction: (() -> Void)?        = nil
    /// Set to `true` externally to programmatically focus this field.
    var externalFocus: Binding<Bool>?        = nil

    @FocusState private var isFocused: Bool
    @State private var showPassword = false

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .foregroundColor(isFocused ? .homeBaseGreen : .secondary)
                    .frame(width: 22)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            }

            Group {
                if isSecure && !showPassword {
                    SecureField(label, text: $text)
                } else {
                    TextField(label, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(autocap)
                        .autocorrectionDisabled()
                }
            }
            .focused($isFocused)
            .submitLabel(submitLabelType)
            .onSubmit { onSubmitAction?() }
            // Sync internal focus state to/from the external binding.
            .onChange(of: isFocused) { _, focused in externalFocus?.wrappedValue = focused }
            .onChange(of: externalFocus?.wrappedValue ?? false) { _, shouldFocus in
                if shouldFocus { isFocused = true }
            }

            // Trailing buttons
            HStack(spacing: 8) {
                // Clear button — only for non-secure fields
                if !isSecure && !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                // Eye toggle — always shown for secure fields
                if isSecure {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showPassword.toggle()
                        }
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15))
                            .foregroundColor(isFocused ? .homeBaseGreen : .secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.homeBaseGreen : Color(.systemGray5), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(isFocused ? 0.06 : 0.03), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - CurrencyField
struct CurrencyField: View {
    let label: String
    @Binding var value: Double

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dollarsign")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isFocused ? .blue : .secondary)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
                .frame(width: 22)

            TextField(label, text: $text)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .onChange(of: text) { _, new in
                    let filtered = new.filter { $0.isNumber || $0 == "." }
                    if filtered != new { text = filtered }
                    value = Double(filtered) ?? 0
                }
                .onAppear {
                    text = value > 0 ? String(format: "%.2f", value) : ""
                }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? Color.blue : Color(.systemGray5),
                    lineWidth: 1.5
                )
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        )
        .shadow(color: .black.opacity(isFocused ? 0.06 : 0.02), radius: 4, y: 2)
    }
}
