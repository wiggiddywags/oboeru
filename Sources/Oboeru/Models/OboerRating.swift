import Foundation

enum OboerRating: Int, CaseIterable {
    case again = 1
    case hard  = 2
    case good  = 3
    case easy  = 4

    var displayName: String {
        switch self {
        case .again: "Again"
        case .hard:  "Hard"
        case .good:  "Good"
        case .easy:  "Easy"
        }
    }

    var keyString: String {
        "\(rawValue)"
    }
}
