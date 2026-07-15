//
//  SeedphraseDisplayView.swift
//  URnetwork
//

import SwiftUI

struct SeedphraseDisplayView: View {

    @EnvironmentObject var themeManager: ThemeManager

    let seedphrase: String
    let onConfirmed: (_ jwt: String) -> Void

    @State private var hasCopied = false

    private let words: [String]

    init(seedphrase: String, onConfirmed: @escaping (String) -> Void) {
        // Normalize: trim whitespace and collapse multiple spaces
        let normalized = seedphrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        self.seedphrase = normalized
        self.onConfirmed = onConfirmed
        self.words = normalized.components(separatedBy: " ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .center) {

                    Text("Your Seedphrase")
                        .foregroundColor(.urWhite)
                        .font(themeManager.currentTheme.titleFont)

                    Spacer().frame(height: 16)

                    Text("⚠️ This is the ONLY time you'll see this.")
                        .foregroundColor(.urYellow)
                        .font(themeManager.currentTheme.bodyFont.bold())
                        .multilineTextAlignment(.center)

                    Text("Write it down and store it somewhere safe. If you lose it, you'll lose access to your account.")
                        .foregroundColor(themeManager.currentTheme.textMutedColor)
                        .font(themeManager.currentTheme.secondaryBodyFont)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 32)

                    // Seedphrase grid display
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: 4) {
                                Text("\(index + 1).")
                                    .foregroundColor(themeManager.currentTheme.textMutedColor)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 24, alignment: .trailing)
                                Text(word)
                                    .foregroundColor(.urWhite)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(themeManager.currentTheme.surfaceColor)
                            .cornerRadius(6)
                        }
                    }
                    .padding(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(themeManager.currentTheme.textMutedColor.opacity(0.3), lineWidth: 1)
                    )

                    Spacer().frame(height: 24)

                    UrButton(
                        text: hasCopied ? "Copied!" : "Copy to Clipboard",
                        action: {
                            UIPasteboard.general.string = seedphrase
                            hasCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                hasCopied = false
                            }
                        },
                        enabled: !hasCopied
                    )

                    Spacer().frame(height: 16)

                    UrButton(
                        text: "I've Saved My Seedphrase",
                        action: {
                            onConfirmed(seedphrase)
                        },
                        enabled: true,
                        isProcessing: false
                    )
                    .tint(.urGreen)

                }
                .padding()
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
            }
            .background(themeManager.currentTheme.backgroundColor.ignoresSafeArea())
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Secure Your Account")
                        .font(themeManager.currentTheme.toolbarTitleFont).fontWeight(.bold)
                }
            }
        }
    }

}

#Preview {
    SeedphraseDisplayView(
        seedphrase: "abandon ability able about above absent absorb abstract absurd abuse access accident account accuse achieve acid acoustic acquire across act action actor active activity",
        onConfirmed: { _ in }
    )
    .environmentObject(ThemeManager.shared)
}
