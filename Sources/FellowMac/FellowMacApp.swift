import AidenCore
import AppKit
import SwiftUI

@main
struct FellowMacApp: App {
  @NSApplicationDelegateAdaptor(FellowAppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel(
    service: FellowAidenService(tokenStore: KeychainTokenStore()))
  @State private var initialized = false
  @State private var menuInserted = true
  var body: some Scene {
    Window("Fellow Mac", id: "main") {
      MainWindow(model: model).task {
        NSApp.activate(ignoringOtherApps: true)
        await initialize()
      }
      .onReceive(
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
      ) { _ in model.pausePolling() }
      .onReceive(
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
      ) { _ in
        model.resumePolling()
        Task { await model.refresh() }
      }
    }.defaultSize(width: 900, height: 660)
      .windowResizability(.contentMinSize)
    MenuBarExtra(isInserted: $menuInserted) {
      CoffeePopover(model: model)
        .task { await initialize() }
        .onReceive(
          NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
        ) { _ in model.pausePolling() }
        .onReceive(
          NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        ) { _ in
          model.resumePolling()
          Task { await model.refresh() }
        }
    } label: {
      Image(systemName: model.isBrewing ? "cup.and.saucer.fill" : "cup.and.saucer")
        .accessibilityLabel("Fellow Mac, \(model.isConnected ? model.statusLabel : "desconectada")")
    }.menuBarExtraStyle(.window)
  }

  private func initialize() async {
    guard !initialized else { return }
    initialized = true
    if ProcessInfo.processInfo.arguments.contains("--demo") {
      await model.enterDemo()
      let arguments = ProcessInfo.processInfo.arguments
      if let index = arguments.firstIndex(of: "--demo-state"),
        arguments.indices.contains(index + 1),
        let scenario = DemoScenario(rawValue: arguments[index + 1])
      {
        await model.setDemoScenario(scenario)
      }
    } else {
      await model.restore()
    }
  }
}

final class FellowAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag {
      sender.windows.first(where: { $0.title == "Fellow Mac" })?.makeKeyAndOrderFront(nil)
    }
    sender.activate(ignoringOtherApps: true)
    return true
  }
}
