import Foundation

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
  case system, light, dark
  var id: String { rawValue }
}

enum StopVisibility: String, Codable, CaseIterable, Identifiable {
  /// Stops appear from a middle zoom level, so the city overview stays calm.
  case zoomed
  /// Stops are drawn at every zoom level.
  case always
  /// Only the selected stop and favourites are drawn.
  case hidden
  var id: String { rawValue }
}

enum MarkerSize: String, Codable, CaseIterable, Identifiable {
  case small, medium, large
  var id: String { rawValue }

  /// Radius in points of the coloured disc of a bus marker.
  var radius: Double {
    switch self {
    case .small: 9.5
    case .medium: 13
    case .large: 16
    }
  }
}

enum RoutePalette: String, Codable, CaseIterable, Identifiable {
  /// The colours Metro Transit publishes.
  case agency
  /// A colour-blind-safe palette, spread so that neighbouring routes differ more.
  case distinct
  /// Routes in grey; only the focused route is coloured.
  case quiet
  var id: String { rawValue }
}

enum ClockFormat: String, Codable, CaseIterable, Identifiable {
  case system, twelveHour, twentyFourHour
  var id: String { rawValue }
}

/// How much the app says about a bus being late or early.
enum DelayDetail: String, CaseIterable, Identifiable {
  case off
  /// "5 min late" next to a live time.
  case minutes
  /// The timetable's time first, then the live countdown and how late or early it is.
  case full
  var id: String { rawValue }
}

/// How often the arrival predictions (160 KB each) are fetched while a stop, a bus, the planner or a list needs them.
enum PredictionRefresh: String, Codable, CaseIterable, Identifiable {
  /// Every minute for a stop, a bus, the planner or watched routes and every two minutes otherwise; on mobile data with
  /// "Save mobile data" on, twice and (in Low Data Mode) four times as long.
  case automatic
  case every30Seconds, everyMinute, everyTwoMinutes, everyFiveMinutes
  /// Only when a stop or bus opens or the rider pulls the list down (watched routes still every five minutes).
  case manual
  var id: String { rawValue }

  /// The chosen gap in seconds; `nil` for automatic and manual.
  var seconds: TimeInterval? {
    switch self {
    case .every30Seconds: 30
    case .everyMinute: 60
    case .everyTwoMinutes: 120
    case .everyFiveMinutes: 300
    case .automatic, .manual: nil
    }
  }
}

enum ArrivalStyle: String, Codable, CaseIterable, Identifiable {
  /// "4 min", switching to a clock time when far off.
  case countdown
  /// Always a clock time.
  case clock
  var id: String { rawValue }
}

/// Everything the user can customise, stored as one JSON value in `UserDefaults`.
///
/// Decoding falls back to the default for any missing key, so adding a setting never loses the existing ones.
struct Preferences: Codable, Equatable {
  // Appearance
  /// The language of the app's text. Kept on the phone only.
  var language: AppLanguage = .system
  var appearance: AppearanceMode = .system
  var routePalette: RoutePalette = .agency
  var markerSize: MarkerSize = .medium
  var showRouteNameOnBuses = true
  var routeLineWidth: Double = 1.0  // multiplier, 0.6...1.6
  var focusStyle: FocusStyle = .hide
  /// How visible faded routes stay when `focusStyle` is `.dim`: 0.02 (almost gone) to 0.3.
  var focusFade: Double = 0.08
  var stopVisibility: StopVisibility = .zoomed
  var showStopNames = true

  // Live data
  /// 0 follows the city's feed (a new one every 30 s); 30 and 60 are battery-saving fixed intervals.
  var updateInterval: Int = 0
  var smoothBusMovement = true
  /// Move each bus along its route at its last speed between reports.
  var estimateBusPositions = true
  var pauseLiveInBackground = true
  /// In automatic mode, on mobile data (or in Low Data Mode) fetch the large trip updates less often.
  var saveMobileData = true
  /// How often predictions are fetched on Wi-Fi, and on mobile data or in Low Data Mode.
  var predictionsOnWiFi: PredictionRefresh = .automatic
  var predictionsOnMobile: PredictionRefresh = .automatic
  /// Download the timetable (7 MB, a few times a year) only on Wi-Fi, unless the phone's copy has expired.
  var timetableOnlyOnWiFi = true

  // Time
  var clockFormat: ClockFormat = .system
  var arrivalStyle: ArrivalStyle = .countdown
  var showDelayDetails = true
  /// With a live time, also show the timetable's own time and, in the full timetable, how far each bus is from it.
  var showScheduledTimes = true

  // Behaviour
  var hapticFeedback = true
  var rememberMapPosition = true

  // Trip planner
  var walkSpeed: WalkSpeed = .normal
  var maxWalkMeters = 800
  var maxTransfers = 3
  /// Time to allow for changing buses, in seconds.
  var transferSeconds = 60
  var accessibleOnly = false
  var journeySort: JourneySort = .departure
  /// How long before leaving to remind the rider, in minutes.
  var reminderLeadMinutes = 5

  // User data
  var savedPlaces: [StoredPlace] = []
  var savedTrips: [SavedTrip] = []
  var recentTrips: [SavedTrip] = []
  var hiddenRoutes: Set<String> = []
  var favoriteStops: [String] = []
  var favoriteRoutes: [String] = []
  var recentStops: [String] = []

  // Notifications about watched routes
  var watchEnabled = false
  var watchedRoutes: [String] = []
  var watchLate = true
  var watchEarly = true
  var watchAlerts = true

  // Last map position
  var lastLatitude: Double?
  var lastLongitude: Double?
  var lastZoom: Double?

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Key.self)
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
    let d = Preferences()
    language = value(.language, d.language)
    appearance = value(.appearance, d.appearance)
    routePalette = value(.routePalette, d.routePalette)
    markerSize = value(.markerSize, d.markerSize)
    showRouteNameOnBuses = value(.showRouteNameOnBuses, d.showRouteNameOnBuses)
    routeLineWidth = min(1.6, max(0.6, value(.routeLineWidth, d.routeLineWidth)))
    focusStyle = value(.focusStyle, d.focusStyle)
    focusFade = min(0.3, max(0.02, value(.focusFade, d.focusFade)))
    stopVisibility = value(.stopVisibility, d.stopVisibility)
    showStopNames = value(.showStopNames, d.showStopNames)
    // Earlier versions stored 5, 10 or 15 seconds; those now mean "follow the feed".
    updateInterval = [30, 60].contains(value(.updateInterval, d.updateInterval)) ? value(.updateInterval, d.updateInterval) : 0
    smoothBusMovement = value(.smoothBusMovement, d.smoothBusMovement)
    estimateBusPositions = value(.estimateBusPositions, d.estimateBusPositions)
    pauseLiveInBackground = value(.pauseLiveInBackground, d.pauseLiveInBackground)
    saveMobileData = value(.saveMobileData, d.saveMobileData)
    predictionsOnWiFi = value(.predictionsOnWiFi, d.predictionsOnWiFi)
    predictionsOnMobile = value(.predictionsOnMobile, d.predictionsOnMobile)
    timetableOnlyOnWiFi = value(.timetableOnlyOnWiFi, d.timetableOnlyOnWiFi)
    clockFormat = value(.clockFormat, d.clockFormat)
    arrivalStyle = value(.arrivalStyle, d.arrivalStyle)
    showDelayDetails = value(.showDelayDetails, d.showDelayDetails)
    showScheduledTimes = value(.showScheduledTimes, d.showScheduledTimes)
    hapticFeedback = value(.hapticFeedback, d.hapticFeedback)
    rememberMapPosition = value(.rememberMapPosition, d.rememberMapPosition)
    walkSpeed = value(.walkSpeed, d.walkSpeed)
    maxWalkMeters = [400, 800, 1200, 2000].contains(value(.maxWalkMeters, d.maxWalkMeters)) ? value(.maxWalkMeters, d.maxWalkMeters) : 800
    maxTransfers = min(3, max(0, value(.maxTransfers, d.maxTransfers)))
    transferSeconds = [60, 180, 300].contains(value(.transferSeconds, d.transferSeconds)) ? value(.transferSeconds, d.transferSeconds) : 60
    accessibleOnly = value(.accessibleOnly, d.accessibleOnly)
    journeySort = value(.journeySort, d.journeySort)
    reminderLeadMinutes = [2, 5, 10, 15].contains(value(.reminderLeadMinutes, d.reminderLeadMinutes)) ? value(.reminderLeadMinutes, d.reminderLeadMinutes) : 5
    savedPlaces = value(.savedPlaces, d.savedPlaces)
    savedTrips = value(.savedTrips, d.savedTrips)
    recentTrips = value(.recentTrips, d.recentTrips)
    hiddenRoutes = value(.hiddenRoutes, d.hiddenRoutes)
    favoriteStops = value(.favoriteStops, d.favoriteStops)
    favoriteRoutes = value(.favoriteRoutes, d.favoriteRoutes)
    recentStops = value(.recentStops, d.recentStops)
    watchEnabled = value(.watchEnabled, d.watchEnabled)
    watchedRoutes = value(.watchedRoutes, d.watchedRoutes)
    watchLate = value(.watchLate, d.watchLate)
    watchEarly = value(.watchEarly, d.watchEarly)
    watchAlerts = value(.watchAlerts, d.watchAlerts)
    lastLatitude = try? c.decodeIfPresent(Double.self, forKey: .lastLatitude)
    lastLongitude = try? c.decodeIfPresent(Double.self, forKey: .lastLongitude)
    lastZoom = try? c.decodeIfPresent(Double.self, forKey: .lastZoom)
  }

  private enum Key: String, CodingKey {
    case language, appearance, routePalette, markerSize, showRouteNameOnBuses, routeLineWidth, focusStyle, focusFade, stopVisibility, showStopNames
    case updateInterval, smoothBusMovement, estimateBusPositions, pauseLiveInBackground, saveMobileData, predictionsOnWiFi, predictionsOnMobile, timetableOnlyOnWiFi
    case clockFormat, arrivalStyle, showDelayDetails, showScheduledTimes
    case hapticFeedback, rememberMapPosition
    case walkSpeed, maxWalkMeters, maxTransfers, transferSeconds, accessibleOnly, journeySort, reminderLeadMinutes
    case savedPlaces, savedTrips, recentTrips
    case hiddenRoutes, favoriteStops, favoriteRoutes, recentStops
    case watchEnabled, watchedRoutes, watchLate, watchEarly, watchAlerts
    case lastLatitude, lastLongitude, lastZoom
  }
}
