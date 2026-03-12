import UIKit

/// Shared card style data used by the Roleplays tab, Dashboard, and Detail screen.
struct CardStyle {
    let iconName: String
    let gradientColors: [UIColor]
}

struct CardStyleProvider {

    static let styles: [String: CardStyle] = [
        "Grocery Shopping": CardStyle(
            iconName: "cart.fill",
            gradientColors: [UIColor(red: 0.66, green: 0.90, blue: 0.81, alpha: 1.0),
                             UIColor(red: 0.34, green: 0.77, blue: 0.59, alpha: 1.0)]
        ),
        "Making Friends": CardStyle(
            iconName: "bubble.left.and.bubble.right.fill",
            gradientColors: [UIColor(red: 0.83, green: 0.65, blue: 1.00, alpha: 1.0),
                             UIColor(red: 0.61, green: 0.45, blue: 0.81, alpha: 1.0)]
        ),
        "Airport Check-in": CardStyle(
            iconName: "airplane",
            gradientColors: [UIColor(red: 0.54, green: 0.81, blue: 0.94, alpha: 1.0),
                             UIColor(red: 0.36, green: 0.61, blue: 0.84, alpha: 1.0)]
        ),
        "Ordering Food": CardStyle(
            iconName: "fork.knife",
            gradientColors: [UIColor(red: 1.00, green: 0.83, blue: 0.65, alpha: 1.0),
                             UIColor(red: 1.00, green: 0.64, blue: 0.42, alpha: 1.0)]
        ),
        "Job Interview": CardStyle(
            iconName: "briefcase.fill",
            gradientColors: [UIColor(red: 0.72, green: 0.78, blue: 1.00, alpha: 1.0),
                             UIColor(red: 0.48, green: 0.56, blue: 0.86, alpha: 1.0)]
        ),
        "Hotel Booking": CardStyle(
            iconName: "bed.double.fill",
            gradientColors: [UIColor(red: 1.00, green: 0.71, blue: 0.76, alpha: 1.0),
                             UIColor(red: 0.95, green: 0.55, blue: 0.62, alpha: 1.0)]
        )
    ]

    static let defaultStyle = CardStyle(
        iconName: "questionmark.circle.fill",
        gradientColors: [UIColor.systemGray4, UIColor.systemGray2]
    )

    static func style(for title: String) -> CardStyle {
        return styles[title] ?? defaultStyle
    }
}
