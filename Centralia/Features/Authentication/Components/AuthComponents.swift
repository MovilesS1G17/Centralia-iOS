import SwiftUI
import UIKit

struct AuthenticationScaffold<Content: View, Footer: View>: View {
    let content: Content
    let footer: Footer

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content
                    Spacer(minLength: CentraliaTheme.Spacing.xLarge)
                    footer
                }
                .frame(maxWidth: 440)
                .frame(minHeight: proxy.size.height - 32)
                .padding(.horizontal, CentraliaTheme.Spacing.large)
                .padding(.vertical, CentraliaTheme.Spacing.medium)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.centraliaCanvas.ignoresSafeArea())
        .foregroundStyle(Color.centraliaInk)
        .tint(Color.centraliaInk)
    }
}

struct CentraliaAuthHeader: View {
    var body: some View {
        VStack(spacing: CentraliaTheme.Spacing.xSmall) {
            Image("CentraliaMark")
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 66)
                .accessibilityHidden(true)

            Text("Centralia")
                .font(CentraliaTheme.Typography.brand)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

struct CentraliaPrimaryButton: View {
    let title: String
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.headline)
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Loading")
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(isDisabled && !isLoading ? Color.centraliaSecondaryText : Color.white)
            .padding(.horizontal, CentraliaTheme.Spacing.medium)
            .padding(.vertical, CentraliaTheme.Spacing.small)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                isDisabled && !isLoading ? Color.centraliaSoftSurface : Color.centraliaInk,
                in: RoundedRectangle(cornerRadius: CentraliaTheme.Radius.control)
            )
        }
        .buttonStyle(CentraliaPressStyle())
        .disabled(isDisabled || isLoading)
        .accessibilityValue(isLoading ? "In progress" : "")
    }
}

struct CentraliaSecondaryButton<Icon: View>: View {
    let title: String
    let icon: Icon
    var isDisabled = false
    let action: () -> Void

    init(
        title: String,
        isDisabled: Bool = false,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon()
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                    .frame(width: 22, height: 22)

                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isDisabled ? Color.centraliaSecondaryText : Color.centraliaInk)
            .padding(.horizontal, CentraliaTheme.Spacing.medium)
            .padding(.vertical, CentraliaTheme.Spacing.small)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                isDisabled ? Color.centraliaSoftSurface : Color.centraliaSurface,
                in: RoundedRectangle(cornerRadius: CentraliaTheme.Radius.control)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CentraliaTheme.Radius.control)
                    .stroke(Color.centraliaDivider, lineWidth: 1)
            }
        }
        .buttonStyle(CentraliaPressStyle())
        .disabled(isDisabled)
    }
}

struct GoogleMark: View {
    var body: some View {
        Image("GoogleMark")
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

struct AuthenticationTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var errorMessage: String?
    var contentType: UITextContentType?
    var keyboardType: UIKeyboardType = .default
    var isSecure = false
    var usesNameInput = false
    var submitLabel: SubmitLabel = .next

    @State private var revealsSecureText = false

    var body: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            Text(label)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: CentraliaTheme.Spacing.small) {
                Group {
                    if isSecure && !revealsSecureText {
                        SecureField(label, text: $text, prompt: prompt)
                    } else {
                        TextField(label, text: $text, prompt: prompt)
                    }
                }
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(usesNameInput ? .words : .never)
                .autocorrectionDisabled(!usesNameInput)
                .submitLabel(submitLabel)
                .accessibilityLabel(label)

                if isSecure {
                    Button {
                        revealsSecureText.toggle()
                    } label: {
                        Image(systemName: revealsSecureText ? "eye.slash" : "eye")
                            .font(.system(size: 20))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealsSecureText ? "Hide password" : "Show password")
                }
            }
            .padding(.leading, CentraliaTheme.Spacing.medium)
            .padding(.trailing, isSecure ? 4 : CentraliaTheme.Spacing.medium)
            .frame(minHeight: 52)
            .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: CentraliaTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: CentraliaTheme.Radius.control)
                    .stroke(errorMessage == nil ? Color.centraliaDivider : Color.centraliaError, lineWidth: 1)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.centraliaError)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error: \(errorMessage)")
            }
        }
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(Color.centraliaSecondaryText)
    }
}

struct AuthenticationDivider: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let text: String

    var body: some View {
        HStack(spacing: CentraliaTheme.Spacing.medium) {
            if !dynamicTypeSize.isAccessibilitySize {
                divider
            }

            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.centraliaSecondaryText)
                .multilineTextAlignment(.center)

            if !dynamicTypeSize.isAccessibilitySize {
                divider
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.centraliaDivider)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct InlineAuthenticationError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(Color.centraliaError)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
    }
}
