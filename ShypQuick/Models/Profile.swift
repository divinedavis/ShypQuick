import Foundation

enum UserRole: String, Codable, CaseIterable, Hashable {
    case customer
    case driver
    case both
}

struct Profile: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var fullName: String?
    var phone: String?
    var role: UserRole
    var avatarUrl: String?
    var rating: Double?
    var homeAddress: String?
    var homeLat: Double?
    var homeLng: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case phone
        case role
        case avatarUrl = "avatar_url"
        case rating
        case homeAddress = "home_address"
        case homeLat = "home_lat"
        case homeLng = "home_lng"
    }
}
