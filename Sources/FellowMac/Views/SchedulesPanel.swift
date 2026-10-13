import AidenCore
import SwiftUI

struct SchedulesPanel: View {
  @ObservedObject var model: AppModel
  @State private var creating = false
  @State private var pendingSchedule: BrewSchedule?
  @State private var deleting = false
  @State private var confirming = false
  @State private var pendingDeviceID: String?
  @State private var pendingContextID: UUID?
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("Café pronto no horário").font(.system(size: 17, weight: .medium))
          Text("Fuso da Aiden: \(model.snapshot?.timezone ?? "indisponível")").font(
            .system(size: 11)
          ).foregroundStyle(CoffeeTheme.muted)
        }
        Spacer()
        Button("Novo horário") { creating = true }.disabled(
          !model.canManageSchedules || model.profiles.isEmpty || model.isRefreshing)
      }
      if !model.canManageSchedules {
        Text("Escolha uma Aiden com fuso confirmado para editar agendamentos.").font(
          .system(size: 12)
        ).foregroundStyle(CoffeeTheme.muted)
      }
      if model.schedules.isEmpty {
        ContentUnavailableView(
          "Nenhum horário agendado", systemImage: "calendar",
          description: Text("Crie um horário com perfil, volume e dias da semana."))
      }
      ForEach(model.schedules) { schedule in
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            VStack(alignment: .leading, spacing: 5) {
              Text(scheduleTime(schedule)).font(.system(size: 27, weight: .light, design: .rounded))
              Text(
                "\(schedule.amountOfWater) ml · \(model.profiles.first(where: { $0.id == schedule.profileId })?.title ?? "Perfil indisponível")"
              ).font(.system(size: 12)).foregroundStyle(CoffeeTheme.muted)
            }
            Spacer()
            Button(schedule.enabled ? "Ativo" : "Pausado") { prepare(schedule, delete: false) }
            Button(role: .destructive) {
              prepare(schedule, delete: true)
            } label: {
              Image(systemName: "trash")
            }.help("Remover agendamento")
          }
          HStack(spacing: 8) {
            ForEach(Array(ScheduleEditor.dayNames.enumerated()), id: \.offset) { index, day in
              Text(day).font(.system(size: 10, weight: .medium)).frame(width: 28, height: 27)
                .background(
                  schedule.days.indices.contains(index) && schedule.days[index]
                    ? CoffeeTheme.copper.opacity(0.24) : CoffeeTheme.panel,
                  in: RoundedRectangle(cornerRadius: 6)
                ).foregroundStyle(CoffeeTheme.cream)
            }
          }
        }.padding(18).background(CoffeeTheme.background, in: RoundedRectangle(cornerRadius: 12))
          .disabled(!model.canManageSchedules || model.isRefreshing)
      }
    }
    .sheet(isPresented: $creating) { ScheduleEditor(model: model) }
    .alert(deleting ? "Remover agendamento?" : "Alterar agendamento?", isPresented: $confirming) {
      Button("Cancelar", role: .cancel) { pendingSchedule = nil }
      Button(deleting ? "Remover" : "Confirmar", role: deleting ? .destructive : nil) {
        guard let schedule = pendingSchedule else { return }
        let deviceID = pendingDeviceID
        let contextID = pendingContextID
        let shouldDelete = deleting
        Task {
          if shouldDelete {
            await model.deleteSchedule(
              schedule, expectedDeviceID: deviceID, expectedContextID: contextID)
          } else {
            await model.toggleSchedule(
              schedule, expectedDeviceID: deviceID, expectedContextID: contextID)
          }
        }
        pendingSchedule = nil
      }
    } message: {
      Text(
        model.isDemo
          ? "A alteração será simulada." : "A alteração será enviada à Aiden selecionada.")
    }
    .onChange(of: model.actionContextID) {
      confirming = false
      pendingSchedule = nil
      creating = false
    }
  }
  private func prepare(_ schedule: BrewSchedule, delete: Bool) {
    pendingSchedule = schedule
    deleting = delete
    pendingDeviceID = model.selectedDeviceID
    pendingContextID = model.actionContextID
    confirming = true
  }
  private func scheduleTime(_ schedule: BrewSchedule) -> String {
    guard (0..<86400).contains(schedule.secondFromStartOfTheDay) else { return "Horário inválido" }
    return String(
      format: "%02d:%02d", schedule.secondFromStartOfTheDay / 3600,
      schedule.secondFromStartOfTheDay % 3600 / 60)
  }
}

struct ScheduleEditor: View {
  static let dayNames = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
  @ObservedObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var hour = 7
  @State private var minute = 30
  @State private var water = 300
  @State private var profileID = ""
  @State private var days = [false, true, true, true, true, true, false]
  @State private var confirming = false
  @State private var deviceID: String?
  @State private var contextID: UUID?
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("Novo agendamento").font(.system(size: 25, weight: .light))
      Text("Café pronto às, no fuso \(model.snapshot?.timezone ?? "indisponível").").font(
        .system(size: 12)
      ).foregroundStyle(CoffeeTheme.muted)
      HStack {
        Picker("Hora", selection: $hour) {
          ForEach(0..<24) { Text(String(format: "%02d", $0)).tag($0) }
        }
        Picker("Minuto", selection: $minute) {
          ForEach(0..<60) { Text(String(format: "%02d", $0)).tag($0) }
        }
      }
      HStack(spacing: 8) {
        ForEach(0..<7) { index in
          Button {
            days[index].toggle()
          } label: {
            Text(Self.dayNames[index]).frame(width: 36, height: 31).background(
              days[index] ? CoffeeTheme.copper : CoffeeTheme.panel,
              in: RoundedRectangle(cornerRadius: 7)
            ).foregroundStyle(days[index] ? CoffeeTheme.background : CoffeeTheme.cream)
          }.buttonStyle(.plain).accessibilityLabel(Self.dayNames[index]).accessibilityAddTraits(
            days[index] ? .isSelected : [])
        }
      }
      Picker("Perfil", selection: $profileID) {
        Text("Escolha o perfil").tag("")
        ForEach(model.profiles) { Text($0.title).tag($0.id) }
      }
      Stepper("Água: \(water) ml", value: $water, in: 150...1500, step: 50)
      if model.isDemo { DemoBadge() }
      HStack {
        Button("Cancelar", role: .cancel) { dismiss() }
        Spacer()
        Button("Criar horário") { confirming = true }.buttonStyle(.borderedProminent).disabled(
          profileID.isEmpty || !days.contains(true) || !model.canManageSchedules || model.isMutating
            || model.isRefreshing)
      }
    }.padding(28).frame(width: 410).background(CoffeeTheme.background).foregroundStyle(
      CoffeeTheme.cream
    ).tint(CoffeeTheme.copper).preferredColorScheme(.dark)
      .alert("Criar este agendamento?", isPresented: $confirming) {
        Button("Cancelar", role: .cancel) {}
        Button("Criar") {
          let draft = ScheduleDraft(
            days: days, secondFromStartOfTheDay: hour * 3600 + minute * 60, amountOfWater: water,
            profileId: profileID)
          let capturedDevice = deviceID
          let capturedContext = contextID
          Task {
            if await model.createSchedule(
              draft, expectedDeviceID: capturedDevice, expectedContextID: capturedContext)
            {
              dismiss()
            }
          }
        }
      } message: {
        Text(
          "Café pronto às \(String(format: "%02d:%02d", hour, minute)), \(water) ml. Fuso: \(model.snapshot?.timezone ?? "indisponível")."
        )
      }
      .onAppear {
        deviceID = model.selectedDeviceID
        contextID = model.actionContextID
      }
      .onChange(of: model.actionContextID) { dismiss() }
  }
}
