import AidenCore
import SwiftUI

struct CoffeePopover: View {
  @ObservedObject var model: AppModel
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    VStack(spacing: 20) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text(model.snapshot?.name ?? "Fellow Mac").font(.system(size: 16, weight: .semibold))
          HStack(spacing: 6) {
            Circle().fill(
              model.isBrewing
                ? CoffeeTheme.copper
                : model.snapshot?.isConnected == true ? Color.green.opacity(0.8) : CoffeeTheme.muted
            ).frame(width: 5, height: 5)
            Text(model.isConnected ? model.statusLabel : "Seu café, perto de você").font(
              .system(size: 12)
            ).foregroundStyle(CoffeeTheme.muted)
          }
        }
        Spacer()
        Button {
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
        } label: {
          Image(systemName: "arrow.up.right.square").font(.system(size: 17))
        }
        .buttonStyle(.plain).foregroundStyle(CoffeeTheme.muted).help("Abrir Fellow Mac")
      }
      if model.isDemo { DemoBadge() }
      if model.isDemo && model.demoScenario == .connecting {
        AidenIllustration().frame(height: 210).opacity(0.6)
        ProgressView("Conectando à nuvem (simulação)").controlSize(.small)
        Text("A demonstração avança em instantes.").font(.system(size: 12)).foregroundStyle(
          CoffeeTheme.muted)
      } else if model.isConnected, !model.devices.isEmpty {
        if model.devices.count > 1 { DevicePicker(model: model) }
        AidenIllustration(brewing: model.isBrewing).frame(height: 198)
        if let snapshot = model.snapshot {
          VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
              if let amount = snapshot.instantWaterQuantity {
                Text(amount.formatted()).font(.system(size: 46, weight: .light, design: .rounded))
                Text("ml").font(.system(size: 17)).foregroundStyle(CoffeeTheme.muted)
              } else {
                Text("Instant Brew").font(.system(size: 27, weight: .light))
              }
            }
            Text(model.instantProfileName).font(.system(size: 12)).foregroundStyle(
              CoffeeTheme.muted)
          }
          BrewButton(model: model)
          FreshnessView(model: model)
        } else {
          Text("Selecione uma Aiden para consultar o estado.").font(.system(size: 13))
            .foregroundStyle(CoffeeTheme.muted)
        }
        HStack(spacing: 10) {
          Button {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
          } label: {
            Label("Perfis e horários", systemImage: "slider.horizontal.3").frame(
              maxWidth: .infinity)
          }
          Button {
            Task { await model.refresh(manual: true) }
          } label: {
            Image(systemName: "arrow.clockwise").frame(width: 25)
          }.disabled(model.isRefreshing || model.isMutating)
        }.buttonStyle(.bordered).controlSize(.large)
      } else {
        AidenIllustration().frame(height: 210).opacity(0.8)
        Text(model.isConnected ? "Nenhuma Aiden encontrada" : "Conecte sua Aiden").font(
          .system(size: 24, weight: .light))
        Text(
          model.isConnected
            ? "Confira os aparelhos da sua conta Fellow e atualize."
            : "Consulte o estado, seus perfis e agendamentos pelo Mac."
        ).font(.system(size: 13)).foregroundStyle(CoffeeTheme.muted).multilineTextAlignment(.center)
        Button(model.isConnected ? "Atualizar aparelhos" : "Conectar conta") {
          if model.isConnected {
            Task { await model.refresh() }
          } else {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
          }
        }.buttonStyle(CoffeePrimaryButton())
        if !model.isConnected {
          Button("Conhecer a demonstração") { Task { await model.enterDemo() } }.buttonStyle(.plain)
            .font(.system(size: 12)).foregroundStyle(CoffeeTheme.copper)
        }
      }
      if let error = model.errorMessage {
        Text(error).font(.system(size: 11)).foregroundStyle(Color.orange).fixedSize(
          horizontal: false, vertical: true)
      }
      if let notice = model.notice {
        Text(notice).font(.system(size: 11)).foregroundStyle(CoffeeTheme.copper).fixedSize(
          horizontal: false, vertical: true)
      }
      HStack {
        Text("FELLOW MAC").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(
          CoffeeTheme.muted)
        Spacer()
        Button("Sair") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11))
          .foregroundStyle(CoffeeTheme.muted)
      }
    }
    .padding(24).frame(width: 350).background(CoffeeTheme.background).foregroundStyle(
      CoffeeTheme.cream
    )
    .preferredColorScheme(.dark)
    .task { await model.refresh() }
  }
}

struct CoffeePrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
      .padding(.vertical, 15)
      .background(CoffeeTheme.copper.opacity(configuration.isPressed ? 0.75 : 1)).foregroundStyle(
        CoffeeTheme.background
      ).clipShape(RoundedRectangle(cornerRadius: 12))
      .opacity(isEnabled ? 1 : 0.45)
  }
}

struct DemoBadge: View {
  var body: some View {
    Label("Demonstração · dados simulados", systemImage: "eye").font(
      .system(size: 11, weight: .medium)
    ).foregroundStyle(CoffeeTheme.copper).padding(.horizontal, 12).padding(.vertical, 6).background(
      CoffeeTheme.copper.opacity(0.1), in: Capsule())
  }
}

struct DevicePicker: View {
  @ObservedObject var model: AppModel
  var body: some View {
    Picker(
      "Aparelho",
      selection: Binding(
        get: { model.selectedDeviceID ?? "" }, set: { id in Task { await model.selectDevice(id) } })
    ) {
      Text("Selecione a Aiden").tag("")
      ForEach(model.devices) { Text($0.name).tag($0.id) }
    }.disabled(model.isMutating).accessibilityLabel("Escolher aparelho Aiden")
  }
}

struct FreshnessView: View {
  @ObservedObject var model: AppModel
  var body: some View {
    VStack(spacing: 4) {
      if let date = model.lastFetchedAt {
        Text(
          "Nuvem consultada às \(date.formatted(date: .omitted, time: .standard))\(model.isStale ? " · desatualizado" : "")"
        )
      } else {
        Text("Aguardando consulta à nuvem")
      }
      if let telemetry = model.snapshot?.telemetryAt {
        Text("Telemetria: \(telemetry.formatted(date: .abbreviated, time: .shortened))")
      } else {
        Text("Horário da telemetria indisponível")
      }
    }.font(.system(size: 10)).foregroundStyle(CoffeeTheme.muted)
  }
}

struct BrewButton: View {
  @ObservedObject var model: AppModel
  @State private var showing = false
  var body: some View {
    VStack(spacing: 7) {
      Button {
        model.prepareBrewConfirmation()
        showing = model.showBrewConfirmation
      } label: {
        Label(
          model.isMutating ? "Enviando comando" : model.isDemo ? "Simular início" : "Iniciar café",
          systemImage: "power")
      }
      .buttonStyle(CoffeePrimaryButton()).disabled(!model.canOfferBrew)
      .alert("Iniciar Instant Brew?", isPresented: $showing) {
        Button("Cancelar", role: .cancel) { model.showBrewConfirmation = false }
        Button(model.isDemo ? "Simular preparo" : "Preparei a cafeteira. Iniciar") {
          Task { await model.confirmBrew() }
        }
      } message: {
        Text(
          "\(model.instantProfileName)\(model.snapshot?.instantWaterQuantity.map { " · \($0) ml" } ?? ""). Usa a configuração Instant Brew da Aiden. Confirme água, café, filtro e recipiente preparados. Início remoto experimental, ainda sem validação física neste app."
        )
      }
      if !model.experimentalBrewEnabled {
        Text("Ative o início experimental em Ajustes.").font(.system(size: 10)).foregroundStyle(
          CoffeeTheme.muted)
      } else if !model.canOfferBrew {
        Text("Atualize e confira o estado e o firmware da Aiden.").font(.system(size: 10))
          .foregroundStyle(CoffeeTheme.muted)
      }
      if model.brewPending {
        Text("Pedido enviado. Confira a cafeteira e atualize antes de liberar outro envio.").font(
          .system(size: 11)
        ).foregroundStyle(CoffeeTheme.copper)
        Button("Conferi a cafeteira") { model.acknowledgeBrew() }.buttonStyle(.bordered).disabled(
          !model.canAcknowledgeBrew)
      }
    }
    .onChange(of: model.actionContextID) { showing = false }
  }
}
