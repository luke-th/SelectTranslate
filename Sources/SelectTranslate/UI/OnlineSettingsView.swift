import SwiftUI

struct OnlineSettingsView: View {
    @ObservedObject var settings: AppSettings

    private enum KeyStatus: Equatable {
        case none, checking, valid(remaining: String), invalid(String)
    }

    @State private var keyDraft = ""
    @State private var keyStatus: KeyStatus = .none
    @State private var models: [OpenRouterModel] = []
    @State private var modelsError: String?
    @State private var modelFilter = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API key")
                    SecureField("", text: $keyDraft, prompt: Text("sk-or-v1-…"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .onSubmit(saveKey)
                }
                HStack {
                    Button("Save") { saveKey() }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces) == settings.openRouterAPIKey)
                    if !settings.openRouterAPIKey.isEmpty {
                        Button("Remove") {
                            keyDraft = ""
                            settings.openRouterAPIKey = ""
                            keyStatus = .none
                        }
                    }
                    Spacer()
                    keyStatusLabel
                }
                Link("Get an API key at openrouter.ai", destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.callout)
            } header: {
                Text("OpenRouter")
            } footer: {
                Text("With a key, text is translated online when Apple's offline pack for that language isn't downloaded — instant, no download sheet. Only then does text leave your Mac; it goes to OpenRouter and the chosen model provider.")
            }

            Section("When to translate online") {
                Picker("Mode", selection: $settings.onlineMode) {
                    ForEach(OnlineTranslationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Section {
                LabeledContent("Selected", value: settings.onlineModelName)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Change model")
                    TextField("", text: $modelFilter, prompt: Text("Search OpenRouter models, e.g. “gpt-4o mini” or “claude”"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                }
                modelList
            } header: {
                Text("Model")
            } footer: {
                Text("Small, fast models are ideal for translation. A typical support message costs a fraction of a cent.")
            }

            Section {
                TextEditor(text: $settings.onlineInstructions)
                    .font(.body)
                    .frame(minHeight: 64)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Additional instructions")
            } footer: {
                Text("Added to every online translation request — e.g. “Keep product names in English” or “Use a formal tone”.")
            }
        }
        .formStyle(.grouped)
        .task {
            keyDraft = settings.openRouterAPIKey
            if !keyDraft.isEmpty { await checkKey() }
            await loadModels()
        }
    }

    // MARK: Key

    private var keyStatusLabel: some View {
        Group {
            switch keyStatus {
            case .none:
                EmptyView()
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                }
            case .valid(let remaining):
                Label("Connected · \(remaining)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .invalid(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout)
    }

    private func saveKey() {
        settings.openRouterAPIKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        keyDraft = settings.openRouterAPIKey
        Task { await checkKey() }
    }

    private func checkKey() async {
        guard !settings.openRouterAPIKey.isEmpty else {
            keyStatus = .none
            return
        }
        keyStatus = .checking
        do {
            let info = try await OpenRouterClient(apiKey: settings.openRouterAPIKey).keyInfo()
            let remaining: String
            if let left = info.limitRemaining {
                remaining = String(format: "$%.2f left", left)
            } else {
                remaining = String(format: "$%.2f used", info.usage)
            }
            keyStatus = .valid(remaining: remaining)
        } catch {
            keyStatus = .invalid(error.localizedDescription)
        }
    }

    // MARK: Models

    /// Every word of the query must appear in the model's name or id.
    private var filteredModels: [OpenRouterModel] {
        let words = modelFilter.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return models.filter { model in
            let haystack = (model.name + " " + model.id).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    @ViewBuilder
    private var modelList: some View {
        let query = modelFilter.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            if let modelsError {
                Label(modelsError, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
            } else if models.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading models…").foregroundStyle(.secondary)
                }
            } else if filteredModels.isEmpty {
                Text("No models match “\(query)”.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredModels.prefix(8)) { model in
                        modelRow(model)
                    }
                    if filteredModels.count > 8 {
                        Text("\(filteredModels.count - 8) more — keep typing to narrow down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(6)
                    }
                }
            }
        }
    }

    private func modelRow(_ model: OpenRouterModel) -> some View {
        let selected = model.id == settings.onlineModelID
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name).font(.body)
                Text("\(model.id) · \(model.priceDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Brand.accent).fontWeight(.semibold)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(selected ? Brand.accent.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            settings.onlineModelID = model.id
            settings.onlineModelName = model.shortName
            modelFilter = ""
        }
    }

    private func loadModels() async {
        do {
            models = try await OpenRouterClient.fetchModels()
            modelsError = nil
        } catch {
            modelsError = "Couldn't load the model list: \(error.localizedDescription)"
        }
    }
}
