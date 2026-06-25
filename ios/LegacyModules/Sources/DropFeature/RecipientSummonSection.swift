import APIClient
import DesignSystem
import SwiftUI

/// Phase 2 preview — invite recipients by phone; summons SMS after drop.
struct RecipientSummonSection: View {
    @Binding var phones: [String]
    @State private var draftPhone = ""
    @State private var verifiedPhone: String?
    @State private var otpCode = ""
    @State private var isSendingOTP = false
    @State private var statusMessage: String?

    let apiClient: LegacyAPIClient

    var body: some View {
        Section {
            Text("Invite someone to return here and unlock your memory. We never send the photo in the text — only a place name and link.")
                .font(LegacyFont.caption)
                .foregroundStyle(LegacyColor.textSecondary)

            ForEach(Array(phones.enumerated()), id: \.offset) { index, phone in
                HStack {
                    Text(phone)
                        .font(LegacyFont.body)
                    Spacer()
                    Button(role: .destructive) {
                        phones.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("Phone number", text: $draftPhone)
                #if os(iOS)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                #endif

            if verifiedPhone == nil {
                Button(isSendingOTP ? "Sending…" : "Verify phone for summons") {
                    Task { await sendOTP() }
                }
                .disabled(draftPhone.trimmingCharacters(in: .whitespaces).isEmpty || isSendingOTP)

                TextField("6-digit code", text: $otpCode)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif

                Button("Confirm code") {
                    Task { await verifyOTP() }
                }
                .disabled(otpCode.count < 6)
            } else {
                Button("Add \(draftPhone)") {
                    let trimmed = draftPhone.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty, !phones.contains(trimmed) {
                        phones.append(trimmed)
                    }
                    draftPhone = ""
                    verifiedPhone = nil
                    otpCode = ""
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textSecondary)
            }
        } header: {
            Text("Summon someone")
        }
    }

    private func sendOTP() async {
        isSendingOTP = true
        defer { isSendingOTP = false }
        do {
            try await apiClient.sendPhoneVerification(phone: draftPhone)
            statusMessage = "Code sent — check your messages."
        } catch {
            statusMessage = "Could not send code. Try again."
        }
    }

    private func verifyOTP() async {
        do {
            let e164 = try await apiClient.verifyPhone(phone: draftPhone, code: otpCode)
            verifiedPhone = e164
            statusMessage = "Phone verified. Tap Add to include this recipient."
        } catch {
            statusMessage = "Invalid code. Try again."
        }
    }
}
