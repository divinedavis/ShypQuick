import Foundation
import UIKit
import Supabase
import Auth

#if canImport(StripePaymentSheet)
import StripePaymentSheet
#endif

/// Apple Pay + Stripe scaffold.
///
/// The customer's card is **authorized** when they confirm the request, and
/// **captured** server-side when the driver marks the job delivered (see the
/// `capture_on_delivered` trigger in `20260510000000_payments.sql`).
///
/// Disabled-by-default: if `STRIPE_PUBLISHABLE_KEY` is empty in `Secrets.plist`
/// or the Stripe iOS SDK isn't linked in this build, `authorize` returns
/// `.notConfigured` and the customer flow falls back to posting a job offer
/// without a payment hold (current behavior).
@MainActor
final class PaymentService {
    static let shared = PaymentService()

    enum AuthorizeResult {
        case authorized(paymentIntentId: String)
        case cancelled
        case notConfigured
        case failed(String)
    }

    private struct Config {
        let publishableKey: String
        let merchantId: String
    }

    private let config: Config?

    /// True when the SDK is linked AND keys are present. UI uses this to
    /// decide whether to show "Pay with Apple Pay" copy on the request button.
    var isConfigured: Bool {
        #if canImport(StripePaymentSheet)
        return config != nil
        #else
        return false
        #endif
    }

    private init() {
        let cfg = Self.loadConfig()
        self.config = cfg
        #if canImport(StripePaymentSheet)
        if let cfg {
            STPAPIClient.shared.publishableKey = cfg.publishableKey
        }
        #endif
    }

    private static func loadConfig() -> Config? {
        guard
            let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: path)
        else { return nil }
        let key = (dict["STRIPE_PUBLISHABLE_KEY"] as? String) ?? ""
        let merchant = (dict["APPLE_PAY_MERCHANT_ID"] as? String) ?? ""
        guard !key.isEmpty, !merchant.isEmpty else { return nil }
        return Config(publishableKey: key, merchantId: merchant)
    }

    // MARK: - Authorize

    /// Authorizes (does not capture) `amountCents` on the customer's card.
    /// Presents the Stripe PaymentSheet with Apple Pay enabled.
    ///
    /// Caller is expected to handle `.notConfigured` by falling through to
    /// the legacy free-flow request path, so partial setup never blocks the
    /// app from working.
    func authorize(amountCents: Int, presenter: UIViewController) async -> AuthorizeResult {
        #if canImport(StripePaymentSheet)
        guard let config else { return .notConfigured }

        let intent: PaymentIntentInfo
        do {
            intent = try await createPaymentIntent(amountCents: amountCents)
        } catch PaymentError.notConfigured {
            return .notConfigured
        } catch {
            return .failed(error.localizedDescription)
        }

        var stripeConfig = PaymentSheet.Configuration()
        stripeConfig.merchantDisplayName = "ShypQuick"
        stripeConfig.applePay = .init(
            merchantId: config.merchantId,
            merchantCountryCode: "US"
        )
        stripeConfig.allowsDelayedPaymentMethods = false

        let sheet = PaymentSheet(
            paymentIntentClientSecret: intent.clientSecret,
            configuration: stripeConfig
        )

        return await withCheckedContinuation { (cont: CheckedContinuation<AuthorizeResult, Never>) in
            sheet.present(from: presenter) { result in
                switch result {
                case .completed:
                    cont.resume(returning: .authorized(paymentIntentId: intent.paymentIntentId))
                case .canceled:
                    cont.resume(returning: .cancelled)
                case .failed(let error):
                    cont.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
        #else
        _ = amountCents
        _ = presenter
        return .notConfigured
        #endif
    }

    // MARK: - Cancel (void hold)

    /// Best-effort void of a held auth. Ignores failures — Stripe auths
    /// expire on their own after ~7 days if not captured.
    @discardableResult
    func cancelHold(offerId: UUID) async -> Bool {
        struct Body: Encodable { let offer_id: String }
        do {
            _ = try await invokeFunction(
                name: "cancel-payment-intent",
                body: Body(offer_id: offerId.uuidString.lowercased()),
                requiresAuth: true
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

    private struct PaymentIntentInfo {
        let clientSecret: String
        let paymentIntentId: String
    }

    private struct CreateBody: Encodable { let amount_cents: Int }
    private struct CreateResponse: Decodable {
        let client_secret: String
        let payment_intent_id: String
    }

    private enum PaymentError: Error {
        case notConfigured
        case http(status: Int, body: String)
        case decode
    }

    private func createPaymentIntent(amountCents: Int) async throws -> PaymentIntentInfo {
        let data = try await invokeFunction(
            name: "create-payment-intent",
            body: CreateBody(amount_cents: amountCents),
            requiresAuth: true
        )
        guard let resp = try? JSONDecoder().decode(CreateResponse.self, from: data) else {
            throw PaymentError.decode
        }
        return PaymentIntentInfo(
            clientSecret: resp.client_secret,
            paymentIntentId: resp.payment_intent_id
        )
    }

    /// Calls a Supabase edge function and returns the raw response data.
    /// Throws `.notConfigured` on 503 so callers can degrade gracefully.
    private func invokeFunction<B: Encodable>(
        name: String,
        body: B,
        requiresAuth: Bool
    ) async throws -> Data {
        let url = SupabaseConfig.url
            .appendingPathComponent("functions/v1")
            .appendingPathComponent(name)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if requiresAuth {
            let session = try await SupabaseService.shared.client.auth.session
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            req.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw PaymentError.http(status: -1, body: "no response")
        }
        if http.statusCode == 503 {
            throw PaymentError.notConfigured
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw PaymentError.http(status: http.statusCode, body: bodyText)
        }
        return data
    }
}
