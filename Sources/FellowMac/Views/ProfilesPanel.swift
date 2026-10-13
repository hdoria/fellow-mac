import AidenCore
import SwiftUI

struct ProfilesPanel: View {
  @ObservedObject var model: AppModel
  @State private var selected: BrewProfile?
  @State private var importLink = ""
  @State private var importConfirmation = false
  @State private var shareURL: URL?
  @State private var importDeviceID: String?
  @State private var importContextID: UUID?
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        TextField("Link do perfil Fellow", text: $importLink).textFieldStyle(.roundedBorder)
        Button("Importar") {
          importDeviceID = model.selectedDeviceID
          importContextID = model.actionContextID
          importConfirmation = true
        }.disabled(
          importLink.isEmpty || model.selectedDeviceID == nil || model.isMutating
            || model.isRefreshing)
      }.alert("Importar perfil para a Aiden?", isPresented: $importConfirmation) {
        Button("Cancelar", role: .cancel) {}
        Button("Importar") {
          let device = importDeviceID
          let context = importContextID
          let link = importLink
          Task {
            await model.importProfile(
              link: link, expectedDeviceID: device, expectedContextID: context)
          }
        }
      } message: {
        Text(
          model.isDemo
            ? "A importação será simulada."
            : "O perfil do link será adicionado ao aparelho selecionado.")
      }
      if model.profiles.isEmpty {
        ContentUnavailableView(
          "Nenhum perfil disponível", systemImage: "slider.horizontal.3",
          description: Text("Atualize o aparelho para consultar os perfis."))
      }
      ForEach(model.profiles) { profile in
        Button {
          selected = selected?.id == profile.id ? nil : profile
          shareURL = nil
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 7) {
              Text(profile.title).font(.system(size: 15, weight: .medium))
              Text(
                profile.ratio.map { "Proporção 1:\($0.formatted())" } ?? "Proporção indisponível"
              ).font(.system(size: 11)).foregroundStyle(CoffeeTheme.muted)
            }
            Spacer()
            Image(systemName: selected?.id == profile.id ? "chevron.up" : "chevron.down").font(
              .system(size: 11)
            ).foregroundStyle(CoffeeTheme.muted)
          }.padding(16).background(CoffeeTheme.background, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
        if selected?.id == profile.id {
          VStack(alignment: .leading, spacing: 10) {
            Text(
              profile.bloomTemperature.map { "Temperatura da pré-infusão: \($0.formatted()) °C" }
                ?? "Temperatura da pré-infusão indisponível")
            Text(
              profile.bloomDuration.map { "Pré-infusão: \($0) segundos" }
                ?? "Duração da pré-infusão indisponível")
            Button(model.isDemo ? "Gerar link simulado" : "Gerar link de compartilhamento") {
              let device = model.selectedDeviceID
              let context = model.actionContextID
              Task {
                shareURL = await model.shareProfile(
                  profile, expectedDeviceID: device, expectedContextID: context)
              }
            }.disabled(model.isMutating || model.isRefreshing)
            if let shareURL {
              ShareLink(item: shareURL) {
                Label("Compartilhar link", systemImage: "square.and.arrow.up")
              }
              Text(shareURL.absoluteString).font(.system(size: 11)).textSelection(.enabled)
                .foregroundStyle(CoffeeTheme.muted)
            }
          }.font(.system(size: 12)).padding(.horizontal, 16)
        }
      }
    }
    .onChange(of: model.actionContextID) {
      selected = nil
      shareURL = nil
      importConfirmation = false
    }
    .onChange(of: model.isConnected) {
      selected = nil
      shareURL = nil
    }
  }
}
