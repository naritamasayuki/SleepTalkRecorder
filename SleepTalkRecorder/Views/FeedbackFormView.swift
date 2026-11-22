import SwiftUI
import UIKit

/// ユーザーからの機能要望やバグ報告を受け付けるフィードバックフォーム画面
struct FeedbackFormView: View {
    @Environment(\.openURL) private var openURL

    @State private var category: FeedbackCategory = .featureRequest
    @State private var message: String = ""
    @State private var includeDeviceInfo: Bool = true
    @State private var alertMessage: String?

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(FeedbackCategory.allCases) { item in
                        Text(item.localizedTitle).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Feedback Type")
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text("Tell us about any issues you encountered or features you would like to see.")
                            .foregroundStyle(.secondary.opacity(0.7))
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }

                    TextEditor(text: $message)
                        .frame(minHeight: 150)
                }
            } header: {
                Text("Details")
            } footer: {
                Text("Your feedback directly helps us improve the app.")
            }

            Section {
                Toggle("Include Device & App Info", isOn: $includeDeviceInfo)
            } footer: {
                Text("Attaches app version, iOS version, and device model to help diagnose bugs faster.")
            }

            Section {
                Button {
                    submitViaMail()
                } label: {
                    Label("Send via Mail", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .disabled(!canSubmit)

                Button {
                    submitViaGitHub()
                } label: {
                    Label("Report on GitHub Issues", systemImage: "safari.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canSubmit)
            }
        }
        .navigationTitle("Feedback & Bug Report")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Feedback",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func submitViaMail() {
        let info = FeedbackDeviceInfo.current
        guard let url = FeedbackFormBuilder.makeMailtoURL(
            category: category,
            message: message,
            includeDeviceInfo: includeDeviceInfo,
            deviceInfo: info
        ) else {
            return
        }

        openURL(url) { accepted in
            if !accepted {
                // メールアプリが未設定の場合は本文をクリップボードにコピーして案内する
                if let content = FeedbackFormBuilder.buildContent(
                    category: category,
                    message: message,
                    includeDeviceInfo: includeDeviceInfo,
                    deviceInfo: info
                ) {
                    UIPasteboard.general.string = "\(content.subject)\n\n\(content.body)"
                }
                alertMessage = String(localized: "Mail app is unavailable. Your message has been copied to the clipboard—please send it to \(FeedbackFormBuilder.supportEmail).")
            }
        }
    }

    private func submitViaGitHub() {
        let info = FeedbackDeviceInfo.current
        guard let url = FeedbackFormBuilder.makeGitHubIssueURL(
            category: category,
            message: message,
            includeDeviceInfo: includeDeviceInfo,
            deviceInfo: info
        ) else {
            return
        }
        openURL(url)
    }
}
