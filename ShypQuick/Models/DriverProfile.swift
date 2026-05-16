import Foundation

// MARK: - Enums

enum DriverVehicleType: String, Codable, CaseIterable, Identifiable, Hashable {
    case car
    case suv
    case pickupTruck = "pickup_truck"
    case cargoVan = "cargo_van"
    case boxTruck = "box_truck"
    case flatbed
    case trailer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .car:         return "Car"
        case .suv:         return "SUV"
        case .pickupTruck: return "Pickup Truck"
        case .cargoVan:    return "Cargo Van"
        case .boxTruck:    return "Box Truck"
        case .flatbed:     return "Flatbed"
        case .trailer:     return "Trailer"
        }
    }
}

enum CrewType: String, Codable, CaseIterable, Identifiable, Hashable {
    case solo
    case twoMan = "two_man"

    var id: String { rawValue }
    var label: String { self == .solo ? "Solo Driver" : "Two-Man Crew" }
}

enum DriverPaymentMethod: String, Codable, CaseIterable, Identifiable, Hashable {
    case ach
    case cashApp = "cash_app"
    case zelle
    case paypal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ach:     return "ACH / Direct Deposit"
        case .cashApp: return "Cash App"
        case .zelle:   return "Zelle"
        case .paypal:  return "PayPal"
        }
    }
}

enum TaxIdType: String, Codable, CaseIterable, Identifiable, Hashable {
    case ssn
    case ein

    var id: String { rawValue }
    var label: String { self == .ssn ? "SSN" : "EIN" }
}

/// A document or photo slot in the private `driver-documents` bucket.
enum DriverDocumentKind: String, CaseIterable {
    case driversLicense
    case insurance
    case vehicleRegistration
    case vehiclePhotoFront
    case vehiclePhotoSide
    case vehiclePhotoCargo

    /// Stable file name so re-uploading a slot overwrites the old object.
    var fileName: String {
        switch self {
        case .driversLicense:      return "drivers-license.jpg"
        case .insurance:           return "insurance.jpg"
        case .vehicleRegistration: return "vehicle-registration.jpg"
        case .vehiclePhotoFront:   return "vehicle-front.jpg"
        case .vehiclePhotoSide:    return "vehicle-side.jpg"
        case .vehiclePhotoCargo:   return "vehicle-cargo.jpg"
        }
    }
}

// MARK: - Driver profile

/// The driver roster row (checklist sections 1-10). Mirrors
/// `public.driver_profiles`. `created_at`/`updated_at` are DB-managed and
/// intentionally omitted so the struct can be upserted as-is.
struct DriverProfile: Codable, Equatable {
    let id: UUID

    // 1. Basic driver information ("yyyy-MM-dd" to match the SQL `date` column)
    var dateOfBirth: String?
    var city: String?
    var state: String?
    var zipCode: String?

    // 2. Vehicle information
    var vehicleType: DriverVehicleType?
    var vehicleLengthFt: Double?
    var payloadCapacityLbs: Int?
    var hasLiftGate: Bool
    var vehicleMake: String?
    var vehicleModel: String?
    var vehicleYear: Int?

    // 3. Equipment availability
    var hasFurnitureDolly: Bool
    var hasApplianceDolly: Bool
    var hasMovingBlankets: Bool
    var hasRatchetStraps: Bool
    var hasPalletJack: Bool
    var hasHandTruck: Bool
    var hasRamp: Bool

    // 4. Crew information
    var crewType: CrewType?
    var additionalHelpersAvailable: Bool
    var whiteGloveCapable: Bool

    // 5. Location & availability
    var primaryServiceArea: String?
    var maxTravelRadiusMi: Int?
    var operatingStates: [String]
    var availableWeekdays: Bool
    var availableWeekends: Bool
    var availableNights: Bool
    var availableOnDemand: Bool

    // 6. Legal & compliance (storage object paths)
    var driversLicensePath: String?
    var insurancePath: String?
    var vehicleRegistrationPath: String?
    var dotNumber: String?
    var backgroundCheckConsent: Bool

    // 7. Delivery experience
    var expFurniture: Bool
    var expAppliance: Bool
    var expMoving: Bool
    var expFreight: Bool
    var expConstructionMaterial: Bool
    var yearsExperience: Int?

    // 8. Specialized services
    var svcStairDeliveries: Bool
    var svcAssemblyDisassembly: Bool
    var svcApplianceHookups: Bool
    var svcHeavyItemHandling: Bool

    // 9. Payment
    var preferredPaymentMethod: DriverPaymentMethod?

    // 10. Vehicle photo uploads (storage object paths)
    var vehiclePhotoFrontPath: String?
    var vehiclePhotoSidePath: String?
    var vehiclePhotoCargoPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case dateOfBirth = "date_of_birth"
        case city
        case state
        case zipCode = "zip_code"
        case vehicleType = "vehicle_type"
        case vehicleLengthFt = "vehicle_length_ft"
        case payloadCapacityLbs = "payload_capacity_lbs"
        case hasLiftGate = "has_lift_gate"
        case vehicleMake = "vehicle_make"
        case vehicleModel = "vehicle_model"
        case vehicleYear = "vehicle_year"
        case hasFurnitureDolly = "has_furniture_dolly"
        case hasApplianceDolly = "has_appliance_dolly"
        case hasMovingBlankets = "has_moving_blankets"
        case hasRatchetStraps = "has_ratchet_straps"
        case hasPalletJack = "has_pallet_jack"
        case hasHandTruck = "has_hand_truck"
        case hasRamp = "has_ramp"
        case crewType = "crew_type"
        case additionalHelpersAvailable = "additional_helpers_available"
        case whiteGloveCapable = "white_glove_capable"
        case primaryServiceArea = "primary_service_area"
        case maxTravelRadiusMi = "max_travel_radius_mi"
        case operatingStates = "operating_states"
        case availableWeekdays = "available_weekdays"
        case availableWeekends = "available_weekends"
        case availableNights = "available_nights"
        case availableOnDemand = "available_on_demand"
        case driversLicensePath = "drivers_license_path"
        case insurancePath = "insurance_path"
        case vehicleRegistrationPath = "vehicle_registration_path"
        case dotNumber = "dot_number"
        case backgroundCheckConsent = "background_check_consent"
        case expFurniture = "exp_furniture"
        case expAppliance = "exp_appliance"
        case expMoving = "exp_moving"
        case expFreight = "exp_freight"
        case expConstructionMaterial = "exp_construction_material"
        case yearsExperience = "years_experience"
        case svcStairDeliveries = "svc_stair_deliveries"
        case svcAssemblyDisassembly = "svc_assembly_disassembly"
        case svcApplianceHookups = "svc_appliance_hookups"
        case svcHeavyItemHandling = "svc_heavy_item_handling"
        case preferredPaymentMethod = "preferred_payment_method"
        case vehiclePhotoFrontPath = "vehicle_photo_front_path"
        case vehiclePhotoSidePath = "vehicle_photo_side_path"
        case vehiclePhotoCargoPath = "vehicle_photo_cargo_path"
    }

    /// An empty roster row for a driver who has not started onboarding.
    static func empty(id: UUID) -> DriverProfile {
        DriverProfile(
            id: id,
            dateOfBirth: nil, city: nil, state: nil, zipCode: nil,
            vehicleType: nil, vehicleLengthFt: nil, payloadCapacityLbs: nil,
            hasLiftGate: false, vehicleMake: nil, vehicleModel: nil, vehicleYear: nil,
            hasFurnitureDolly: false, hasApplianceDolly: false, hasMovingBlankets: false,
            hasRatchetStraps: false, hasPalletJack: false, hasHandTruck: false, hasRamp: false,
            crewType: nil, additionalHelpersAvailable: false, whiteGloveCapable: false,
            primaryServiceArea: nil, maxTravelRadiusMi: nil, operatingStates: [],
            availableWeekdays: false, availableWeekends: false,
            availableNights: false, availableOnDemand: false,
            driversLicensePath: nil, insurancePath: nil, vehicleRegistrationPath: nil,
            dotNumber: nil, backgroundCheckConsent: false,
            expFurniture: false, expAppliance: false, expMoving: false,
            expFreight: false, expConstructionMaterial: false, yearsExperience: nil,
            svcStairDeliveries: false, svcAssemblyDisassembly: false,
            svcApplianceHookups: false, svcHeavyItemHandling: false,
            preferredPaymentMethod: nil,
            vehiclePhotoFrontPath: nil, vehiclePhotoSidePath: nil, vehiclePhotoCargoPath: nil
        )
    }

    /// Whether the core dispatch-critical fields are filled in.
    var isComplete: Bool {
        dateOfBirth != nil
            && !(city ?? "").isEmpty
            && !(state ?? "").isEmpty
            && !(zipCode ?? "").isEmpty
            && vehicleType != nil
            && !(vehicleMake ?? "").isEmpty
            && !(vehicleModel ?? "").isEmpty
            && vehicleYear != nil
            && crewType != nil
            && preferredPaymentMethod != nil
            && driversLicensePath != nil
            && insurancePath != nil
            && backgroundCheckConsent
    }
}

// MARK: - Tax info

/// Isolated SSN/EIN row. Mirrors `public.driver_tax_info`.
struct DriverTaxInfo: Codable, Equatable {
    let id: UUID
    var taxIdType: TaxIdType?
    var taxId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taxIdType = "tax_id_type"
        case taxId = "tax_id"
    }

    static func empty(id: UUID) -> DriverTaxInfo {
        DriverTaxInfo(id: id, taxIdType: nil, taxId: nil)
    }
}
