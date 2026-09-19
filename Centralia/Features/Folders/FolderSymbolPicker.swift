import SwiftUI

struct FolderSymbolPicker: View {
    @Binding var selection: FolderSymbol

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: CentraliaTheme.Spacing.small),
        count: 4
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: CentraliaTheme.Spacing.small) {
            ForEach(FolderSymbol.allCases) { symbol in
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol.rawValue)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(
                            selection == symbol
                                ? Color.centraliaCanvas
                                : Color.centraliaInk
                        )
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            selection == symbol
                                ? Color.centraliaInk
                                : Color.centraliaSoftSurface,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay {
                            if selection != symbol {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.centraliaDivider, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(CentraliaPressStyle())
                .accessibilityLabel(symbol.accessibilityName)
                .accessibilityAddTraits(selection == symbol ? .isSelected : [])
                .accessibilityIdentifier("folderSymbol.\(symbol.rawValue)")
            }
        }
    }
}
