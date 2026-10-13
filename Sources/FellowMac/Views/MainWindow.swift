import AidenCore
import SwiftUI

struct MainWindow: View {
  @ObservedObject var model: AppModel
  @State private var section: Section = .status
  enum Section: String, CaseIterable, Identifiable {
    case status = "Estado"
    case profiles = "Perfis"
    case schedules = "Agendamentos"
    case settings = "Ajustes"
    var id: String { rawValue }
    var icon: String {
      switch self {
      case .status: "cup.and.saucer"
      case .profiles: "slider.horizontal.3"
      case .schedules: "calendar"
      case .settings: "gearshape"
      }
    }
  }
  var body: some View {
    Group {
      if !model.isConnected {
        LoginView(model: model)
      } else {
        NavigationSplitView {
          VStack(alignment: .leading, spacing: 26) {
            Text("FELLOW\nMAC").font(.system(size: 19, weight: .medium)).tracking(4).lineSpacing(4)
              .padding(.horizontal, 14).padding(.top, 24)
            VStack(spacing: 6) {
              ForEach(Section.allCases) { item in
                Button {
                  section = item
                } label: {
                  Label(item.rawValue, systemImage: item.icon).font(.system(size: 13)).frame(
                    maxWidth: .infinity, alignment: .leading
                  ).padding(12)
                    .background(
                      section == item ? CoffeeTheme.copper.opacity(0.13) : Color.clear,
                      in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(section == item ? CoffeeTheme.cream : CoffeeTheme.muted)
                }.buttonStyle(.plain)
              }
            }
            Spacer()
            Text("Cliente independente\npara sua Aiden").font(.system(size: 10)).foregroundStyle(
              CoffeeTheme.muted
            ).padding(.horizontal, 14).padding(.bottom, 20)
          }.padding(10).background(CoffeeTheme.background).navigationSplitViewColumnWidth(180)
        } detail: {
          ScrollView {
            VStack(alignment: .leading, spacing: 22) {
              HStack {
                VStack(alignment: .leading, spacing: 6) {
                  Text(section.rawValue).font(.system(size: 27, weight: .light))
                  Text(model.snapshot?.name ?? "Escolha seu aparelho").font(.system(size: 12))
                    .foregroundStyle(CoffeeTheme.muted)
                }
                Spacer()
                if model.isDemo { DemoBadge() }
                Button {
                  Task { await model.refresh(manual: true) }
                } label: {
                  Image(systemName: "arrow.clockwise")
                }.disabled(model.isRefreshing || model.isMutating).help("Atualizar")
              }
              if model.devices.count > 1 { DevicePicker(model: model) }
              if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12))
                  .foregroundStyle(.orange).padding(12).frame(
                    maxWidth: .infinity, alignment: .leading
                  ).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
              }
              if let notice = model.notice {
                Text(notice).font(.system(size: 12)).foregroundStyle(CoffeeTheme.copper)
              }
              switch section {
              case .status: StatusPanel(model: model)
              case .profiles: ProfilesPanel(model: model)
              case .schedules: SchedulesPanel(model: model)
              case .settings: SettingsPanel(model: model)
              }
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
          }.background(CoffeeTheme.panel)
        }
      }
    }.frame(minWidth: 780, minHeight: 600).preferredColorScheme(.dark).tint(CoffeeTheme.copper)
      .foregroundStyle(CoffeeTheme.cream)
  }
}

struct StatusPanel: View {
  @ObservedObject var model: AppModel
  var body: some View {
    if model.isDemo && model.demoScenario == .connecting {
      VStack(spacing: 18) {
        ProgressView().controlSize(.large)
        Text("Conectando à nuvem").font(.system(size: 21, weight: .light))
        Text("Simulação de conexão. Você pode trocar o cenário ou sair da demonstração.").font(
          .system(size: 12)
        ).foregroundStyle(CoffeeTheme.muted)
      }.frame(maxWidth: .infinity, minHeight: 300)
    } else if let brewer = model.snapshot {
      HStack(spacing: 28) {
        AidenIllustration(brewing: model.isBrewing).frame(width: 265, height: 265)
        VStack(alignment: .leading, spacing: 15) {
          Text(model.statusLabel).font(.system(size: 23, weight: .light))
          if let amount = brewer.instantWaterQuantity {
            Text("\(amount) ml").font(.system(size: 38, weight: .light, design: .rounded))
          }
          Text(model.instantProfileName).font(.system(size: 13)).foregroundStyle(CoffeeTheme.muted)
          BrewButton(model: model)
        }.frame(maxWidth: .infinity)
      }
      Divider()
      Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 13) {
        GridRow {
          Text("Conexão")
          Text(brewer.isConnected.map { $0 ? "Conectada" : "Sem conexão" } ?? "Indisponível")
        }
        GridRow {
          Text("Firmware")
          Text(brewer.firmwareVersion ?? "Indisponível")
        }
        GridRow {
          Text("Fuso da Aiden")
          Text(brewer.timezone ?? "Indisponível")
        }
        GridRow {
          Text("Água")
          Text(
            brewer.missingWater.map { $0 ? "Falta água" : "Sem alerta de falta" } ?? "Indisponível")
        }
        GridRow {
          Text("Tampa")
          Text(brewer.lidClosed.map { $0 ? "Fechada" : "Aberta" } ?? "Indisponível")
        }
        GridRow {
          Text("Recipiente")
          Text(brewer.carafePresent.map { $0 ? "Detectado" : "Não detectado" } ?? "Indisponível")
        }
      }.font(.system(size: 12)).foregroundStyle(CoffeeTheme.muted)
      FreshnessView(model: model).frame(maxWidth: .infinity).padding(.top, 12)
    } else {
      ContentUnavailableView(
        model.devices.isEmpty ? "Nenhuma Aiden na conta" : "Selecione uma Aiden",
        systemImage: "cup.and.saucer",
        description: Text("Selecione um aparelho ou atualize sua conta para consultar o estado."))
    }
  }
}

struct SettingsPanel: View {
  @ObservedObject var model: AppModel
  @State private var logoutConfirmation = false
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Início remoto").font(.system(size: 17, weight: .medium))
        Toggle("Habilitar Instant Brew experimental", isOn: $model.experimentalBrewEnabled)
          .disabled(model.isMutating)
        Text(
          "Exige firmware 1.5.16 ou superior, consulta recente e confirmação a cada envio. Usa a receita já configurada na Aiden. O efeito físico ainda precisa ser validado."
        ).font(.system(size: 12)).foregroundStyle(CoffeeTheme.muted)
      }
      Divider()
      VStack(alignment: .leading, spacing: 10) {
        Text("Atualizações").font(.system(size: 17, weight: .medium))
        Text(
          "Consulta à nuvem a cada 60 segundos. O horário de consulta e a telemetria do aparelho aparecem separadamente. A atualização pausa quando o Mac entra em repouso."
        ).font(.system(size: 12)).foregroundStyle(CoffeeTheme.muted)
      }
      Divider()
      if model.isDemo {
        VStack(alignment: .leading, spacing: 12) {
          Text("Cenário da demonstração").font(.system(size: 17, weight: .medium))
          Picker(
            "Cenário",
            selection: Binding(
              get: { model.demoScenario },
              set: { value in Task { await model.setDemoScenario(value) } })
          ) {
            ForEach(DemoScenario.allCases) { Text($0.label).tag($0) }
          }.pickerStyle(.menu).disabled(model.isMutating)
          Text(
            "Todos os dados e comandos deste modo são simulados. A demonstração funciona sem rede."
          ).font(.system(size: 12)).foregroundStyle(CoffeeTheme.muted)
        }
      } else {
        Button("Abrir demonstração") { Task { await model.enterDemo() } }.disabled(
          model.isMutating || model.isLoading)
      }
      Divider()
      Text(
        "Fellow Mac · projeto independente\nTokens guardados no Keychain. A senha é descartada após o login."
      ).font(.system(size: 12)).foregroundStyle(CoffeeTheme.muted)
      Button(model.isDemo ? "Sair da demonstração" : "Desconectar conta", role: .destructive) {
        logoutConfirmation = true
      }
      .alert(
        model.isDemo ? "Sair da demonstração?" : "Desconectar a conta Fellow?",
        isPresented: $logoutConfirmation
      ) {
        Button("Cancelar", role: .cancel) {}
        Button("Desconectar", role: .destructive) { Task { await model.logout() } }
      } message: {
        Text(
          model.isDemo
            ? "Os dados simulados serão removidos da tela."
            : "Os tokens serão removidos do Keychain e os dados da conta serão limpos.")
      }
    }.font(.system(size: 13))
  }
}
