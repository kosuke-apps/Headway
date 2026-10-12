import SwiftUI
import UserNotifications

@main
struct HeadwayApp: App {
  @State private var model: AppModel

  init() {
    let model = AppModel(settings: AppSettings())
    _model = State(initialValue: model)
    LanguageState.shared.apply(model.settings.values.language)
    UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    WatchBackground.register(model)
  }

  var body: some Scene {
    WindowGroup {
      LanguageRoot {
        RootView()
          .environment(model)
          .task { await model.start() }
      }
    }
  }
}
