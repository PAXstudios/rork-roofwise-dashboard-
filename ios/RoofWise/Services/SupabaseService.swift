import Foundation
import Supabase

/// Thin wrapper around the shared SupabaseClient. Use `SupabaseService.client`
/// for all Supabase calls (auth, postgrest, storage).
enum SupabaseService {
    static let client: SupabaseClient = makeClient()

    private static func makeClient() -> SupabaseClient {
        let urlString = APIKeys.supabaseURL
        let anonKey = APIKeys.supabaseAnonKey
        let options = SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(flowType: .pkce)
        )
        guard let url = URL(string: urlString), !anonKey.isEmpty else {
            // Build with a placeholder so the app doesn't crash on launch when
            // env injection is missing. Auth/data calls will fail with a clear
            // error surfaced to the user.
            print("[Supabase] Missing URL or anon key — falling back to placeholder client")
            return SupabaseClient(
                supabaseURL: URL(string: "https://placeholder.supabase.co")!,
                supabaseKey: "placeholder",
                options: options
            )
        }
        print("[Supabase] Client init for \(url.host ?? urlString) (flowType=pkce)")
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey, options: options)
    }
}
