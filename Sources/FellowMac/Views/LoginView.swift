import SwiftUI

struct LoginView: View {
  @ObservedObject var model: AppModel
  @State private var email = ""
  @State private var password = ""
  @FocusState private var focusedField: Field?
  enum Field { case email, password }
  var body: some View {
    HStack(spacing: 42) {
      VStack(spacing: 12) {
        AidenIllustration().frame(width: 270, height: 295)
        Text("Um bom café.\nUm lugar perto.").font(.system(size: 29, weight: .light))
          .multilineTextAlignment(.center)
      }.frame(maxWidth: .infinity)
      VStack(alignment: .leading, spacing: 18) {
        Text("FELLOW MAC").font(.system(size: 10, weight: .medium)).tracking(3).foregroundStyle(
          CoffeeTheme.copper)
        Text("Conecte sua Aiden").font(.system(size: 28, weight: .light))
        Text("Use a conta do app Fellow. Os tokens ficam no Keychain do Mac.").font(
          .system(size: 13)
        ).foregroundStyle(CoffeeTheme.muted)
        VStack(alignment: .leading, spacing: 7) {
          Text("Email").font(.system(size: 12))
          TextField("voce@exemplo.com", text: $email).textContentType(.username).focused(
            $focusedField, equals: .email)
          Text("Senha").font(.system(size: 12)).padding(.top, 8)
          SecureField("Senha da conta Fellow", text: $password).textContentType(.password).focused(
            $focusedField, equals: .password
          ).onSubmit(connect)
        }.textFieldStyle(.roundedBorder)
        Button(action: connect) {
          HStack {
            if model.isLoading { ProgressView().controlSize(.small) }
            Text(model.isLoading ? "Conectando" : "Conectar conta")
          }
        }.buttonStyle(CoffeePrimaryButton()).disabled(
          email.isEmpty || password.isEmpty || model.isLoading)
        if let error = model.errorMessage {
          Text(error).font(.system(size: 12)).foregroundStyle(.orange)
        }
        Button("Entrar em demonstração") {
          password = ""
          Task { await model.enterDemo() }
        }.buttonStyle(.plain).foregroundStyle(CoffeeTheme.copper)
        Text("Cliente independente. Pareamento e Wi-Fi continuam no app oficial da Fellow.").font(
          .system(size: 11)
        ).foregroundStyle(CoffeeTheme.muted)
      }.frame(width: 290)
    }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity).background(
      CoffeeTheme.background
    ).foregroundStyle(CoffeeTheme.cream)
      .onAppear { focusedField = .email }.onDisappear { password = "" }
  }
  private func connect() {
    guard !model.isLoading, !password.isEmpty else { return }
    let submittedPassword = password
    password = ""
    Task { await model.login(email: email, password: submittedPassword) }
  }
}
