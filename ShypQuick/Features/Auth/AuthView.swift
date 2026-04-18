import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var session: SessionStore
    @State private var showEmailAuth = false
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var role: UserRole = .customer
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            gradient

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 120)

                    // ── Branding ──
                    VStack(spacing: 6) {
                        Text("Send")
                            .font(.title.bold())
                            .foregroundStyle(.secondary.opacity(0.4))
                        HStack(spacing: 8) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 36)
                            Text("ShypQuick")
                                .font(.largeTitle.bold())
                        }
                        Text("Deliver")
                            .font(.title.bold())
                            .foregroundStyle(.secondary.opacity(0.4))
                    }

                    Spacer(minLength: 60)

                    // ── Tagline ──
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "shippingbox.and.arrow.backward.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                        Text("Big items.\nFast delivery.")
                            .font(.title.bold())
                            .foregroundStyle(.white)
                        Text("On-demand delivery for furniture, appliances, and everything in between.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 40)

                    // ── Buttons ──
                    VStack(spacing: 12) {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleSignIn(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)
                        .cornerRadius(25)

                        Button {
                            showEmailAuth = true
                        } label: {
                            HStack {
                                Image(systemName: "envelope.fill")
                                Text("Continue with email")
                            }
                            .bold()
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 25))
                            .foregroundStyle(.white)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 40)
                }
                .frame(minHeight: UIScreen.main.bounds.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showEmailAuth) {
            emailAuthSheet
        }
    }

    // MARK: - Gradient background

    private var gradient: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.systemBackground),
                Color.blue.opacity(0.3),
                Color.blue.opacity(0.7),
                Color.blue
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Email auth sheet

    private var emailAuthSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        if isSignUp {
                            TextField("Full name", text: $fullName)
                                .textFieldStyle(.roundedBorder)
                        }
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)

                        if isSignUp {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("I want to sign up as")
                                    .font(.footnote.bold())
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    roleCard(choice: .customer, title: "Customer", subtitle: "Send packages", icon: "shippingbox.fill")
                                    roleCard(choice: .driver, title: "Driver", subtitle: "Deliver & earn", icon: "car.fill")
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }

                    Button(action: submitEmail) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text(isSignUp ? "Create account" : "Sign in")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button(isSignUp ? "Have an account? Sign in" : "New here? Create account") {
                        isSignUp.toggle()
                    }
                    .font(.footnote)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isSignUp ? "Create account" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEmailAuth = false }
                }
            }
        }
    }

    // MARK: - Role card

    @ViewBuilder
    private func roleCard(choice: UserRole, title: String, subtitle: String, icon: String) -> some View {
        let isSelected = role == choice
        Button { role = choice } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                Text(title).font(.subheadline.bold())
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(subtitle).font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func submitEmail() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                if isSignUp {
                    try await session.signUp(email: email, password: password, fullName: fullName, role: role)
                } else {
                    try await session.signIn(email: email, password: password)
                }
                showEmailAuth = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Could not read Apple credential."
                return
            }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            Task {
                isLoading = true
                defer { isLoading = false }
                do {
                    try await session.signInWithApple(idToken: idToken, fullName: name.isEmpty ? nil : name)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }
}
