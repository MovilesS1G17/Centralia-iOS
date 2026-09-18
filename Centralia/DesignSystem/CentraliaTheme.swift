import SwiftUI
import UIKit

enum CentraliaTheme {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let xxLarge: CGFloat = 48
    }

    enum Radius {
        static let control: CGFloat = 14
        static let sheet: CGFloat = 24
    }

    enum Typography {
        static var brand: Font {
            availableCustomFont(
                named: "Joan-Regular",
                size: 30,
                relativeTo: .largeTitle,
                fallback: .system(.largeTitle, design: .serif)
            )
        }

        static var display: Font {
            availableCustomFont(
                named: "InstrumentSerif-Regular",
                size: 35,
                relativeTo: .largeTitle,
                fallback: .system(.largeTitle, design: .serif)
            )
        }

        static var sectionTitle: Font {
            availableCustomFont(
                named: "InstrumentSerif-Regular",
                size: 24,
                relativeTo: .title2,
                fallback: .system(.title2, design: .serif)
            )
        }

        private static func availableCustomFont(
            named name: String,
            size: CGFloat,
            relativeTo textStyle: Font.TextStyle,
            fallback: Font
        ) -> Font {
            guard UIFont(name: name, size: size) != nil else {
                return fallback
            }

            return .custom(name, size: size, relativeTo: textStyle)
        }
    }
}

extension Color {
    static let centraliaCanvas = Color("WarmCanvas")
    static let centraliaInk = Color("Ink")
    static let centraliaSurface = Color("Surface")
    static let centraliaSoftSurface = Color("SoftSurface")
    static let centraliaDivider = Color("Divider")
    static let centraliaSecondaryText = Color("SecondaryText")
    static let centraliaVideoSand = Color("VideoSand")
    static let centraliaVideoMint = Color("VideoMint")
    static let centraliaVideoClay = Color("VideoClay")
    static let centraliaVideoLavender = Color("VideoLavender")
}

struct CentraliaPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
