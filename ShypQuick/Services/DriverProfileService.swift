import Foundation
import Supabase

/// Loads and persists the driver roster row, the isolated tax-info row, and
/// uploads compliance documents / vehicle photos to the private
/// `driver-documents` storage bucket.
@MainActor
final class DriverProfileService {
    static let shared = DriverProfileService()
    private init() {}

    private var client: SupabaseClient { SupabaseService.shared.client }

    private static let bucket = "driver-documents"

    // MARK: - Roster row

    /// Returns the driver's roster row, or `nil` if onboarding hasn't started.
    func load(driverId: UUID) async throws -> DriverProfile? {
        let rows: [DriverProfile] = try await client
            .from("driver_profiles")
            .select()
            .eq("id", value: driverId)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Inserts or updates the driver's roster row.
    func save(_ profile: DriverProfile) async throws {
        try await client
            .from("driver_profiles")
            .upsert(profile, onConflict: "id")
            .execute()
    }

    // MARK: - Tax info (isolated table)

    func loadTaxInfo(driverId: UUID) async throws -> DriverTaxInfo? {
        let rows: [DriverTaxInfo] = try await client
            .from("driver_tax_info")
            .select()
            .eq("id", value: driverId)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func saveTaxInfo(_ info: DriverTaxInfo) async throws {
        try await client
            .from("driver_tax_info")
            .upsert(info, onConflict: "id")
            .execute()
    }

    // MARK: - Document / photo storage

    /// Uploads a JPEG to the driver's private folder and returns the object
    /// path to store on the roster row. Re-uploading a slot overwrites it.
    func uploadDocument(_ jpeg: Data, kind: DriverDocumentKind, driverId: UUID) async throws -> String {
        // Storage RLS compares the folder against `auth.uid()::text`, which
        // Postgres formats lowercase; Swift's uuidString is uppercase.
        let path = "\(driverId.uuidString.lowercased())/\(kind.fileName)"
        try await client.storage
            .from(Self.bucket)
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return path
    }

    /// Mints a short-lived signed URL so a stored document can be previewed.
    func signedURL(forPath path: String, expiresIn seconds: Int = 60 * 60) async -> URL? {
        do {
            return try await client.storage
                .from(Self.bucket)
                .createSignedURL(path: path, expiresIn: seconds)
        } catch {
            print("DriverProfileService.signedURL error:", error)
            return nil
        }
    }
}
