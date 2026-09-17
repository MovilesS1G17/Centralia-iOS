import SwiftUI

enum LegalDocument: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms:
            "Terms of Service"
        case .privacy:
            "Privacy Policy"
        }
    }
}

struct LegalDocumentSheet: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(document.title, systemImage: "doc.text")
            } description: {
                Text("The approved document or destination URL has not been included in the design artifacts yet.")
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct LegalAgreementText: View {
    let openDocument: (LegalDocument) -> Void

    private let agreement = try? AttributedString(
        markdown: "By continuing, you agree to the [Terms of Service](centralia://terms) and acknowledge the [Privacy Policy](centralia://privacy)."
    )

    var body: some View {
        Text(agreement ?? AttributedString("By continuing, you agree to the Terms of Service and acknowledge the Privacy Policy."))
            .font(.caption)
            .foregroundStyle(Color.centraliaSecondaryText)
            .multilineTextAlignment(.center)
            .environment(\.openURL, OpenURLAction { url in
                switch url.host {
                case "terms":
                    openDocument(.terms)
                    return .handled
                case "privacy":
                    openDocument(.privacy)
                    return .handled
                default:
                    return .discarded
                }
            })
    }
}
