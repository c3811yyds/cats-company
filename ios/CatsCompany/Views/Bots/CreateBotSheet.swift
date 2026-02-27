import SwiftUI

struct CreateBotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    let onCreated: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("机器人名称", text: $displayName)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("基本信息")
                } footer: {
                    Text("名称将作为机器人的显示名，用户名会自动生成")
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(CatColor.danger)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("创建机器人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task { await createBot() }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }

    private func createBot() async {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        // Generate a username from display name
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let username = "bot-\(slug.prefix(16))-\(Int.random(in: 1000...9999))"

        do {
            _ = try await APIClient.shared.createBot(username: username, displayName: name)
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}
