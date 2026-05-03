import Foundation
import Supabase
import Auth

enum SupabaseConfig {
    static var url: URL {
        guard
            let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: path),
            let raw = dict["SUPABASE_URL"] as? String,
            let url = URL(string: raw)
        else {
            fatalError("Missing SUPABASE_URL in Secrets.plist")
        }
        return url
    }

    static var anonKey: String {
        guard
            let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: path),
            let key = dict["SUPABASE_ANON_KEY"] as? String
        else {
            fatalError("Missing SUPABASE_ANON_KEY in Secrets.plist")
        }
        return key
    }
}

final class SupabaseService {
    static let shared = SupabaseService()
    let client: SupabaseClient

    private init() {
        let options = SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                storage: KeychainAuthStorage()
            )
        )
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: options
        )
    }
}
