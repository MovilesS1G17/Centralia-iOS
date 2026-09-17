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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(Color.centraliaInk, in: RoundedRectangle(cornerRadius: CentraliaTheme.Radius.control))
        }
        .buttonStyle(CentraliaPressStyle())
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled && !isLoading ? 0.48 : 1)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.centraliaInk)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: CentraliaTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: CentraliaTheme.Radius.control)
                    .stroke(Color.centraliaDivider, lineWidth: 1)
            }
        }
        .buttonStyle(CentraliaPressStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.48 : 1)
    }
}

struct GoogleMark: View {
    var body: some View {
        Text("G")
            .font(.system(size: 21, weight: .bold, design: .rounded))
            .foregroundStyle(
                AngularGradient(
                    colors: [
                        Color(red: 0.26, green: 0.52, blue: 0.96),
                        Color(red: 0.92, green: 0.26, blue: 0.21),
                        Color(red: 0.98, green: 0.74, blue: 0.02),
                        Color(red: 0.20, green: 0.66, blue: 0.33),
                        Color(red: 0.26, green: 0.52, blue: 0.96)
                    ],
                    center: .center
                )
            )
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
    var submitLabel: SubmitLabel = .next

    @State private var revealsSecureText = false

    var body: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            Text(label)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: CentraliaTheme.Spacing.small) {
                Group {
                    if isSecure && !revealsSecureText {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)

                if isSecure {
                    Button {
                        revealsSecureText.toggle()
                    } label: {
                        Image(systemName: revealsSecureText ? "eye.slash" : "eye")
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
                    .stroke(errorMessage == nil ? Color.centraliaDivider : Color.red, lineWidth: 1)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error: \(errorMessage)")
            }
        }
    }
}

struct AuthenticationDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: CentraliaTheme.Spacing.medium) {
            Rectangle()
                .fill(Color.centraliaDivider)
                .frame(height: 1)

            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.centraliaSecondaryText)
                .fixedSize()

            Rectangle()
                .fill(Color.centraliaDivider)
                .frame(height: 1)
        }
    }
}

struct InlineAuthenticationError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
    }
}
