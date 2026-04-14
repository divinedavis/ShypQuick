import SwiftUI

struct AuthView: View {
    @EnvironmentObject var session: SessionStore
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "shippingbox.and.arrow.backward.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text("ShypQuick")
                    .font(.largeTitle.bold())
                Text("On-demand delivery, on your terms.")
                    .foregroundStyle(.secondary)

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
                }
                .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }

                Button(action: submit) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(isSignUp ? "Create account" : "Sign in")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Button(isSignUp ? "Have an account? Sign in" : "New here? Create account") {
                    isSignUp.toggle()
                }
                .font(.footnote)

                Spacer()
            }
            .padding()
        }
    }

    private func submit() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                if isSignUp {
                    try await session.signUp(email: email, password: password, fullName: fullName)
                } else {
                    try await session.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
