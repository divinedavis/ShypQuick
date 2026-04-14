import Foundation

enum UserRole: String, Codable, CaseIterable {
    case customer
    case driver
    case both
}

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var fullName: String?
    var phone: String?
    var role: UserRole
    var avatarUrl: String?
    var rating: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case phone
        case role
        case avatarUrl = "avatar_url"
        case rating
    }
}
