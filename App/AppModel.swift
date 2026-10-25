import CoreLocation
import Foundation
import HeadwayCore
import os
import Observation

/// What the app is for at the moment. The map stays alive underneath the other two.
enum AppMode: String, CaseIterable, Identifiable {
  case map, info, plan
  var id: String { rawValue }
}

/// What the sheet over the map is showing.
/// Where "Back" on the chip over the map leads: the list the map was opened from.
enum FocusReturn: Equatable {
  case mode(AppMode)
  case sheet(ActiveSheet)
}

enum ActiveSheet: Identifiable, Equatable {
  case stop(String)
  case bus(String)  // vehicle id
  /// A trip on its service date that no bus is reporting on (yet): its timetable, stop by stop.
  case trip(String, ServiceDate)
  case journey
  case settings
  case routes
  case search

  /// Stops and buses share one identity so that selecting another stop updates the open sheet instead of
  /// dismissing and presenting a new one.
  var id: String {
    switch self {
    case .stop, .bus, .trip, .journey: "detail"
    case .settings: "settings"
    case .routes: "routes"
    case .search: "search"
    }
  }

  var isDetail: Bool {
    switch self {
    case .stop, .bus, .trip, .journey: true
    default: false
    }
  }
}

/// Asks the map to move. Each request has a fresh `id` so that asking for the same place twice still animates.
struct CameraRequest: Equatable {
  let id = UUID()
  let latitude: Double
  let longitude: Double
  /// The zoom to use; the map never zooms out for a request, only in.
  let minimumZoom: Double
}

/// Asks the map to show all of some coordinates at once.
struct FitRequest: Equatable {
  let id = UUID()
  let coordinates: [Coordinate]
}

/// App-wide state: the timetable, live buses, what is selected, and the arrivals shown for it.
@MainActor @Observable
final class AppModel {
  enum Phase {
    case loading
    case ready
    case failed(String)
  }

  let settings: AppSettings
  let location = LocationController()
  let plan = PlanModel()
  @ObservationIgnored let watch = WatchNotifier()
  /// Set when the rider asked to watch a route but notifications are not allowed for the app.
  var notificationsDenied = false

  private(set) var phase: Phase = .loading
  private(set) var schedule: Schedule?
  private(set) var vehicles: [VehicleSample] = [] {
    didSet {
      // A bus that stopped reporting cannot wait in the dock.
      if let id = dockedVehicleID, !vehicles.contains(where: { $0.id == id }) { closeDockedBus() }
    }
  }
  private(set) var predictions: [TripPrediction] = []
  private(set) var alerts: [ServiceAlert] = []
  /// How punctual routes and stops have been, and how far live predictions have been off (from recordings).
  private(set) var punctuality: PunctualityTable = .empty
  /// Buses that are far from the line their trip should follow, so probably on a detour.
  private(set) var offRouteVehicleIDs: Set<String> = []
  /// When on, the stop sheet and timetable also show routes the user chose to hide.
  var showHiddenRoutes = false
  private(set) var arrivals: [Arrival] = []
  /// What the map draws: route lines, stops and the route network. Loaded from a saved copy at launch, so that the map
  /// is complete before the timetable has been parsed.
  private(set) var overlay: MapOverlay?
  /// Direction (0 or 1) of each live bus's trip.
  private(set) var vehicleDirections: [String: Int] = [:]
  /// The pattern number in each live bus's destination ("2" for "2-Airport"): D buses to the airport and to Epic
  /// Campus are told apart by it.
  private(set) var vehiclePatterns: [String: String] = [:]
  /// The way each live bus's trip runs, as a letter for the marker ("E" for Eastbound); loops have none.
  private(set) var vehicleHeadings: [String: String] = [:]
  /// The destination ("2-EPIC CAMPUS") of each live bus's trip.
  private(set) var vehicleHeadsigns: [String: String] = [:]
  /// The screen to go back to from the map's focus chip, when the focus was started from a list (an alert's "Show on
  /// map", the routes list).
  private(set) var focusReturn: FocusReturn?
  /// Scheduled service of each route and direction (`outlookKey`), for "no buses right now" versus "not running today".
  private(set) var outlooks: [String: ServiceOutlook] = [:]
  /// True when the board shows service after the next three hours because nothing else is coming.
  private(set) var arrivalsAreLater = false
  /// The stop to go back to from a bus opened out of that stop's board.
  private(set) var returnStopID: String?
  /// When the vehicle feed last answered successfully.
  private(set) var lastLiveUpdate: Date?
  /// When a feed newer than the one before last arrived (the phone's clock): the live card says how long the city's feed has
  /// been standing still when positions get old.
  private(set) var feedChangedAt: Date?
  /// True when the most recent poll failed.
  private(set) var liveFailing = false

  var sheet: ActiveSheet? {
    didSet { if sheet != oldValue { selectionChanged() } }
  }
  /// A stop or a bus the rider put away (swiped its sheet down, opened the menu): it waits in the dock at the bottom of
  /// the map, still marked on it, and a tap brings its sheet back. A journey has its own place (`mapJourney`).
  private(set) var dockedStopID: String?
  private(set) var dockedVehicleID: String?
  var mode: AppMode = .map {
    didSet {
      guard mode != oldValue else { return }
      menuOpen = false
      if mode != .map, sheet != nil { minimizeSheet() }
      refreshStatus()
      if mode != .map { ensurePredictions() }  // predictions are needed in every mode but the plain map
    }
  }
  /// The side menu. A sheet is drawn above everything else, so opening the menu puts the sheet away first (a journey
  /// then waits in the bar at the bottom of the map).
  var menuOpen = false {
    didSet { if menuOpen, !oldValue, sheet != nil { minimizeSheet() } }
  }
  /// True while the planner shows a pushed screen (a journey's details): the edge swipe then goes back, not to the menu.
  var planPushed = false
  /// A place the rider long-pressed on the map, waiting for them to say what to do with it.
  var droppedPin: PlanPoint?
  /// The journey drawn on the map, with the lines to draw.
  private(set) var mapJourney: Journey?
  private(set) var journeyLines: [JourneyPolyline] = []
  private(set) var fitRequest: FitRequest?
  private(set) var status: ServiceStatus?
  /// Seconds each live bus is behind (positive) or ahead of its timetable, from the trip updates.
  private(set) var vehicleDelays: [String: Double] = [:]
  /// What each bus with no trip in the position feed (out of service, or waiting at a terminal) will run next, if known.
  private(set) var idleBuses: [String: IdleBus] = [:]
  /// True while the live-status card is open: it needs the delays too.
  var liveSummaryOpen = false
  /// What the user asked the map to show on its own (a route, an alert, late buses); everything else is hidden or dimmed.
  private(set) var focus = MapFocus()
  /// Routes under the finger after a tap on overlapping lines, waiting for the rider to say which one.
  var routeChoices: [String] = []
  private(set) var cameraRequest: CameraRequest?

  @ObservationIgnored private let client = RealtimeClient(onTransfer: { feed, bytes in
    let metered = NetworkStatus.shared.isMetered
    Task { @MainActor in DataMeter.shared.record(DataKind(feed), bytes: bytes, metered: metered) }
  })
  @ObservationIgnored private var pollTask: Task<Void, Never>?
  @ObservationIgnored private var started = false
  @ObservationIgnored private var isActive = true
  @ObservationIgnored private var lastAlertFetch = Date.distantPast
  @ObservationIgnored private var lastTripsFetch = Date.distantPast
  @ObservationIgnored private var feedTimestamp: Date?
  @ObservationIgnored private var feedPeriod: TimeInterval = 30
  @ObservationIgnored private var publishLag = PublishLag()
  @ObservationIgnored private var slowDataBusy = false
  // Where the vehicle poll is in its cycle. Kept here, not in the loop, so that restarting the loop (the app coming back to the
  // front, Refresh, the watchdog) carries on with the same schedule instead of asking at once and then retrying every two seconds.
  @ObservationIgnored private var nextPollAt = Date.distantPast
  @ObservationIgnored private var pollUnchanged = 0
  @ObservationIgnored private var pollLastChange = Date.distantPast
  @ObservationIgnored private var pollScheduled = false  // the next request is the one timed for the next feed
  @ObservationIgnored private var fetchingPredictions = false
  @ObservationIgnored private var periods: [TimeInterval] = []
  @ObservationIgnored private var watchdogSince = Date()
  @ObservationIgnored private var lastWatchdogRestart = Date.distantPast

  static let scheduleURL = URL(string: "https://transitdata.cityofmadison.com/GTFS/mmt_gtfs.zip")!

  init(settings: AppSettings) {
    self.settings = settings
  }

  // MARK: Derived state

  var selectedStopID: String? {
    if case .stop(let id) = sheet { return id }
    return nil
  }

  var selectedVehicle: VehicleSample? {
    if case .bus(let id) = sheet { return vehicles.first { $0.id == id } }
    return nil
  }

  /// The bus in the dock, while it is still reporting.
  var dockedVehicle: VehicleSample? { dockedVehicleID.flatMap { id in vehicles.first { $0.id == id } } }

  /// What the map marks as chosen: the open stop or bus, or else the one waiting in the dock.
  var markedStopID: String? { selectedStopID ?? dockedStopID }
  var markedVehicleID: String? { selectedVehicle?.id ?? dockedVehicle?.id }

  /// True when there is anything to bring back from the bottom of the map.
  var hasDock: Bool { dockedStopID != nil || dockedVehicle != nil || mapJourney != nil }

  var orderedRoutes: [Route] { overlay?.orderedRoutes ?? [] }

  func route(_ id: String) -> Route? { overlay?.routes[id] ?? schedule?.routes[id] }

  /// Route ids serving each stop, ordered like the route list.
  var routesByStop: [String: [String]] { overlay?.network.routesByStop ?? [:] }

  /// Key of `outlooks`: a route in one direction, or in both (nil).
  nonisolated static func outlookKey(route: String, direction: Int?) -> String { "\(route)|\(direction.map(String.init) ?? "*")" }

  func outlook(route: String, direction: Int?) -> ServiceOutlook? { outlooks[Self.outlookKey(route: route, direction: direction)] }

  /// Buses on a route (in one direction, or both) in the live feed.
  func busCount(route: String, direction: Int?) -> Int {
    vehicles.reduce(0) { count, vehicle in
      guard vehicle.routeID == route else { return count }
      if let direction, vehicleDirections[vehicle.id] != direction { return count }
      return count + 1
    }
  }

  /// How the buses of a route (one direction, one destination) are doing: how many, and how many late, on time and early.
  func fleet(route: String, direction: Int? = nil, headsign: String? = nil) -> FleetBreakdown {
    var result = FleetBreakdown()
    for vehicle in vehicles where vehicle.routeID == route && !vehicle.tripID.isEmpty {
      if let direction, vehicleDirections[vehicle.id] != direction { continue }
      if let headsign, vehicleHeadsigns[vehicle.id] != headsign { continue }
      result.total += 1
      guard let seconds = vehicleDelays[vehicle.id] else { continue }
      if seconds > ServiceStatusBuilder.lateThreshold {
        result.late += 1
      } else if seconds < ServiceStatusBuilder.earlyThreshold {
        result.early += 1
      } else {
        result.onTime += 1
      }
    }
    return result
  }

  /// The same for every bus on a trip.
  func fleetAll() -> FleetBreakdown {
    var result = FleetBreakdown()
    for vehicle in vehicles where !vehicle.tripID.isEmpty {
      result.total += 1
      guard let seconds = vehicleDelays[vehicle.id] else { continue }
      if seconds > ServiceStatusBuilder.lateThreshold {
        result.late += 1
      } else if seconds < ServiceStatusBuilder.earlyThreshold {
        result.early += 1
      } else {
        result.onTime += 1
      }
    }
    return result
  }

  /// Fetches the buses again right away instead of waiting for the next beat of the city's feed.
  func refreshNow() {
    isActive = true
    restartPolling(immediately: true, force: true)
    ensurePredictions()
  }

  /// Buses on the road that are not on a trip.
  var idleBusCount: Int { vehicles.filter { $0.tripID.isEmpty }.count }

  /// Which way buses go at a stop ("Southbound"), when the feed says.
  func stopSide(_ id: String?) -> String? {
    guard let id else { return nil }
    return Compass.bound(schedule?.stops[id]?.facing ?? overlay?.stops[id]?.facing)
  }

  /// The direction of a trip in words ("Southbound"), from the feed's direction name.
  func tripDirection(_ tripID: String) -> String? {
    guard let trip = schedule?.trips[tripID], !trip.directionName.isEmpty else { return nil }
    return Self.compassName(trip.directionName)
  }

  /// A stop's name with the way its buses go, to tell apart the two stops of the same name on either side of a street.
  func stopTitle(_ point: PlanPoint) -> String {
    guard let side = stopSide(point.stopID) else { return point.name }
    return "\(point.name) (\(side))"
  }

  /// The ways a route runs (one entry per direction).
  func variants(of route: String) -> [RouteVariant] { overlay?.network.variants(of: route) ?? [] }

  var hiddenRoutes: Set<String> { settings.values.hiddenRoutes }

  /// How far the stop board reaches back and forward from now. The rider can ask for earlier departures and for later ones;
  /// opening another stop, or pulling the board down to refresh it, goes back to what is near now.
  private(set) var boardEarlier: TimeInterval = 0
  private(set) var boardWindow: TimeInterval = AppModel.defaultBoardWindow
  private static let defaultBoardWindow: TimeInterval = 3 * 3600

  func showEarlierDepartures() {
    boardEarlier = min(boardEarlier + 3600, 12 * 3600)
    refreshArrivals()
  }

  func showLaterDepartures() {
    boardWindow = min(boardWindow + 3 * 3600, Self.longestBoardWindow)
    refreshArrivals()
  }

  /// True when the board reaches further than its first view: earlier departures are shown, or later ones were asked for.
  var boardIsExtended: Bool { boardEarlier > 0 || boardWindow > Self.defaultBoardWindow }

  /// True while asking for later departures can still show more (the board reaches a day ahead at most).
  var canShowLaterDepartures: Bool { boardWindow < Self.longestBoardWindow }

  private static let longestBoardWindow: TimeInterval = 24 * 3600

  /// How many coming departures the board lists: 40 for each three hours it reaches, so that every tap on "Later
  /// departures" adds rows (with a fixed 40, the second tap showed nothing new at a busy stop).
  private var boardLimit: Int { 40 * Int((boardWindow / (3 * 3600)).rounded(.up)) }

  /// Back to the departures around now, and fresh data.
  func resetBoard() {
    boardEarlier = 0
    boardWindow = Self.defaultBoardWindow
    refreshArrivals()
  }

  /// Arrivals for the selected stop, without routes the user hides (unless they asked to see them).
  var boardArrivals: [Arrival] {
    showHiddenRoutes ? arrivals : arrivals.filter { !hiddenRoutes.contains($0.routeID) }
  }

  var hiddenArrivalCount: Int { arrivals.count - arrivals.filter { !hiddenRoutes.contains($0.routeID) }.count }

  /// Routes serving a stop, without hidden ones unless the user asked to see them.
  func visibleRoutes(atStop id: String) -> [String] {
    let all = routesByStop[id] ?? []
    return showHiddenRoutes ? all : all.filter { !hiddenRoutes.contains($0) }
  }

  /// Alerts in force right now.
  var activeAlerts: [ServiceAlert] {
    let now = Date()
    return alerts.filter { $0.isActive(at: now) }
  }

  /// Alerts in force, without those that only concern routes the rider hides.
  var visibleActiveAlerts: [ServiceAlert] {
    activeAlerts.filter { $0.routeIDs.isEmpty || $0.routeIDs.contains { !hiddenRoutes.contains($0) } }
  }

  var upcomingAlerts: [ServiceAlert] {
    let now = Date()
    return alerts.filter { $0.isUpcoming(at: now) }
  }

  /// Routes with an alert in force: drawn dashed on the map.
  var alertRouteIDs: Set<String> { Set(activeAlerts.flatMap(\.routeIDs)) }

  func timeText() -> TimeText {
    TimeText(
      timeZone: schedule?.timeZone ?? TimeZone(identifier: "America/Chicago")!,
      clockFormat: settings.values.clockFormat,
      arrivalStyle: settings.values.arrivalStyle)
  }

  // MARK: Lifecycle

  func start() async {
    guard !started else { return }
    started = true
    NetworkStatus.shared.start()
    watchdogSince = Date()
    restartPolling(immediately: true)
    startWatchdog()
    Task { await loadPunctuality() }
    // The saved copy of the map data shows every route right away; the timetable is parsed behind it.
    let began = CFAbsoluteTimeGetCurrent()
    if let saved = await Task.detached(priority: .userInitiated, operation: { OverlayStore.load() }).value, overlay == nil {
      overlay = saved
      launchLog.info("saved map data read in \(Int((CFAbsoluteTimeGetCurrent() - began) * 1000)) ms")
    }
    await loadSchedule()
  }

  enum RefreshResult { case updated, upToDate, failed }

  /// Downloads the timetable now, whatever the cache says.
  func refreshTimetable() async -> RefreshResult {
    await refreshFromNetwork(force: true)
  }

  func retry() async {
    phase = .loading
    await loadSchedule()
  }

  /// Live polling pauses in the background when the user chose that. Only a real move between foreground and background
  /// counts: the app is still in front, and must keep polling, while Control Center or a system alert has it "inactive".
  func setActive(_ active: Bool) {
    guard active != isActive else { return }
    isActive = active
    restartPolling(immediately: active)
  }

  // MARK: Selection and camera

  func selectStop(_ id: String, moveCamera: Bool = true) {
    guard let stop = schedule?.stops[id] else { return }
    settings.noteRecent(stop: id)
    Haptics.selection(enabled: settings.values.hapticFeedback)
    dockedStopID = nil
    sheet = .stop(id)
    if moveCamera { fly(to: stop.latitude, stop.longitude, minimumZoom: 15) }
  }

  func selectBus(_ vehicleID: String, moveCamera: Bool = true) {
    returnStopID = selectedStopID ?? (sheet?.isDetail == true ? returnStopID : nil)
    dockedVehicleID = nil
    sheet = .bus(vehicleID)
    guard let vehicle = vehicles.first(where: { $0.id == vehicleID }) else { return }
    if moveCamera { fly(to: vehicle.latitude, vehicle.longitude, minimumZoom: 14) }
    if !vehicle.routeID.isEmpty, !focusShows(vehicle) { focusOnTrip(of: vehicle) }
  }

  /// True when the map's focus leaves a bus where it is, so that opening the bus changes nothing on the map. A focus the
  /// bus itself started is not kept: opening another bus from its sheet (through a stop's board) shows that bus's trip.
  private func focusShows(_ vehicle: VehicleSample) -> Bool {
    Self.focus(focus, shows: vehicle.id, route: vehicle.routeID, direction: vehicleDirections[vehicle.id], headsign: vehicleHeadsigns[vehicle.id])
  }

  nonisolated static func focus(_ focus: MapFocus, shows vehicleID: String, route: String, direction: Int?, headsign: String?) -> Bool {
    guard focus.isActive, !focus.fromBus, focus.routes.contains(route) else { return false }
    if let wanted = focus.direction, let own = direction, own != wanted { return false }
    if let wanted = focus.headsign, let own = headsign, own != wanted { return false }
    return focus.highlightedBuses.isEmpty || focus.highlightedBuses[vehicleID] != nil
  }

  /// Opens the timetable of a trip, stop by stop: for a row of the stop board that no bus is reporting on yet. The line of
  /// the trip goes on the map like a bus's; the camera stays where it is (the rider is looking at a stop).
  func selectTrip(_ tripID: String, on date: ServiceDate) {
    guard let trip = schedule?.trips[tripID] else { return }
    returnStopID = selectedStopID ?? (sheet?.isDetail == true ? returnStopID : nil)
    dockedVehicleID = nil
    if let bus = vehicles.first(where: { $0.tripID == tripID }) {
      selectBus(bus.id, moveCamera: false)  // a bus has turned up on it: show the live trip
      return
    }
    sheet = .trip(tripID, date)
    if !focusShowsTrip(route: trip.routeID, direction: trip.directionID, headsign: trip.headsign) {
      focusOnTrip(route: trip.routeID, direction: trip.directionID, headsign: trip.headsign)
    }
  }

  private func focusShowsTrip(route: String, direction: Int, headsign: String) -> Bool {
    let current = focus
    guard current.isActive, !current.fromBus, current.routes.contains(route) else { return false }
    if let wanted = current.direction, wanted != direction { return false }
    if let wanted = current.headsign, wanted != headsign { return false }
    return current.highlightedBuses.isEmpty
  }

  /// Shows the line of one bus's own trip: its route, its direction and, where the route has several destinations in
  /// that direction (D2 to Epic Campus, to Verona), only the line to its destination.
  private func focusOnTrip(of vehicle: VehicleSample) {
    focusOnTrip(route: vehicle.routeID, direction: vehicleDirections[vehicle.id], headsign: vehicleHeadsigns[vehicle.id])
  }

  private func focusOnTrip(route: String, direction: Int?, headsign: String?) {
    let all = direction.map { overlay?.network.patterns(of: route, direction: $0) ?? [] } ?? []
    focusReturn = nil
    focus = Self.tripFocus(route: route, direction: direction, headsign: headsign, patterns: all)
  }

  /// The focus for a bus's trip: `patterns` are all the destinations of its route in its direction.
  nonisolated static func tripFocus(route: String, direction: Int?, headsign: String?, patterns: [RoutePattern]) -> MapFocus {
    var next = MapFocus.route(route, direction: direction)
    if patterns.count > 1, let headsign, let pattern = patterns.first(where: { $0.headsign == headsign }) {
      next.headsign = pattern.headsign
      next.headsignStops = Set(pattern.stops)
    }
    next.fromBus = true
    return next
  }

  // MARK: Dock

  /// Puts the open stop or bus away into the dock (the sheet closes, the map keeps it marked). Anything else just closes.
  func minimizeSheet() {
    switch sheet {
    case .stop(let id)?: dockedStopID = id
    case .bus(let id)?: dockedVehicleID = id
    case .trip?: if focus.fromBus { focus = MapFocus() }  // a timetable has no marker on the map to wait in the dock
    default: break
    }
    sheet = nil
  }

  /// Brings the sheet of the docked stop back.
  func reopenDockedStop() {
    guard let id = dockedStopID else { return }
    dockedStopID = nil
    sheet = .stop(id)
  }

  /// Brings the sheet of the docked bus back, with the line of its trip on the map.
  func reopenDockedBus() {
    guard let vehicle = dockedVehicle else { return }
    dockedVehicleID = nil
    sheet = .bus(vehicle.id)
    if !vehicle.routeID.isEmpty, !focusShows(vehicle), !(focus.fromBus && focus.routes.contains(vehicle.routeID)) { focusOnTrip(of: vehicle) }
  }

  func closeDockedStop() { dockedStopID = nil }

  /// Lets go of the docked bus, and of the line it had put on the map.
  func closeDockedBus() {
    dockedVehicleID = nil
    if focus.fromBus { focus = MapFocus() }
  }

  // MARK: Punctuality

  private func loadPunctuality() async {
    guard let url = Bundle.main.url(forResource: "punctuality", withExtension: "json") else { return }
    let table = await Task.detached(priority: .utility) { () -> PunctualityTable? in
      guard let data = try? Data(contentsOf: url) else { return nil }
      return try? PunctualityTable.decode(data)
    }.value
    if let table { punctuality = table }
  }

  /// Past punctuality of `route` (at `stop`, if given) at this time of day and week, when there is enough history.
  func reliability(route: String, stop: String?, at date: Date = Date()) -> PunctualityTable.Match? {
    punctuality.match(route: route, stop: stop, at: date, in: schedule?.timeZone ?? TimeZone(identifier: "America/Chicago")!)
  }

  /// When a live bus has come in 9 of 10 past cases for a prediction this far ahead.
  func window(for arrival: Arrival, now: Date = Date()) -> (earliest: Date, latest: Date)? {
    guard arrival.status == .live,
      let offsets = punctuality.window(predictedIn: arrival.expected.timeIntervalSince(now))
    else { return nil }
    return (max(now, arrival.expected.addingTimeInterval(offsets.earliest)), arrival.expected.addingTimeInterval(offsets.latest))
  }

  // MARK: Journeys

  /// The planner's options as set in Settings.
  func plannerOptions() -> PlanOptions {
    let prefs = settings.values
    var options = PlanOptions()
    options.walkSpeed = prefs.walkSpeed.metersPerSecond
    options.maxWalkMeters = Double(prefs.maxWalkMeters)
    options.maxRides = prefs.maxTransfers + 1
    options.minTransferSeconds = Double(prefs.transferSeconds)
    options.accessibleOnly = prefs.accessibleOnly
    return options
  }

  func planContext() -> PlanContext {
    PlanContext(
      schedule: schedule, predictions: predictions, vehicles: vehicles, here: location.location, options: plannerOptions())
  }

  /// Runs the planner with what the app currently knows, and remembers the search.
  func searchJourneys() async {
    if let from = plan.from, let to = plan.to { settings.noteRecent(from: from, to: to, vias: plan.storedVias) }
    await plan.search(planContext())
  }

  func loadLaterJourneys() async { await plan.loadLater(planContext()) }
  func loadEarlierJourneys() async { await plan.loadEarlier(planContext()) }

  /// Draws a journey on the map and opens its summary.
  func showOnMap(_ journey: Journey) {
    guard let schedule else { return }
    let lines = journey.polylines(schedule: schedule)
    mapJourney = journey
    journeyLines = lines
    mode = .map
    sheet = .journey
    fitRequest = FitRequest(coordinates: lines.flatMap(\.coordinates))
  }

  func clearJourney() {
    mapJourney = nil
    journeyLines = []
    if sheet == .journey { sheet = nil }
  }

  /// Starts a trip from the rider's location (or the previous start) to `point`, in the planner.
  func startDirections(to point: PlanPoint) {
    plan.to = .point(point)
    plan.vias = []
    if plan.from == nil || plan.from == plan.to { plan.from = .myLocation }
    plan.clearResults()
    mapJourney = nil
    journeyLines = []
    mode = .plan
    location.start()
  }

  /// Starts a trip from `point` to wherever the rider wants to go.
  func startDirections(from point: PlanPoint) {
    plan.from = .point(point)
    plan.vias = []
    if plan.to == plan.from { plan.to = nil }
    plan.clearResults()
    mapJourney = nil
    journeyLines = []
    mode = .plan
  }

  func clearSelection() {
    returnStopID = nil
    let closesBus = switch sheet {
    case .bus?, .trip?: true
    default: false
    }
    sheet = nil
    if closesBus, focus.fromBus { focus = MapFocus() }
  }

  /// Shows only `id` (in one direction, or both). Choosing from a list zooms out to the whole route; tapping the map
  /// does not move the camera.
  func focusRoute(_ id: String, direction: Int? = nil, fit: Bool = true) {
    routeChoices = []
    focusReturn = returnTarget()
    focus = .route(id, direction: direction)
    ensurePredictions()
    if mode != .map { mode = .map }
    if fit { fitToFocus() }
  }

  /// A tap on route lines: one route is looked at on its own (or let go of when it already is); several ask which.
  func tapRoutes(_ ids: [String]) {
    let ordered = ids.sorted { (route($0)?.sortOrder ?? .max, $0) < (route($1)?.sortOrder ?? .max, $1) }
    if ordered.count == 1, let id = ordered.first {
      if focus.routes == [id], focus.highlightedStops.isEmpty, focus.highlightedBuses.isEmpty {
        focus = MapFocus()
      } else {
        focusRoute(id, direction: nil, fit: false)
      }
      routeChoices = []
    } else {
      routeChoices = ordered
      ensurePredictions()
    }
  }

  func clearFocus() {
    focus = MapFocus()
    focusReturn = nil
    routeChoices = []
  }

  /// The list the map is being opened from, to come back to.
  private func returnTarget() -> FocusReturn? {
    if mode != .map { return .mode(mode) }
    if sheet == .routes { return .sheet(.routes) }
    return nil
  }

  /// Lets go of the focus and goes back to where it was started.
  func returnFromFocus() {
    let target = focusReturn
    clearFocus()
    switch target {
    case .mode(let mode)?: self.mode = mode
    case .sheet(let sheet)?: self.sheet = sheet
    case nil: break
    }
  }

  /// Changes the direction of the route in focus (nil for both).
  func setFocusDirection(_ direction: Int?) {
    guard focus.routes.count == 1 else { return }
    focus.direction = direction
    focus.headsign = nil
    focus.headsignStops = []
    focus.fromBus = false
  }

  /// Narrows the route in focus to one of its destinations, or back to the whole direction when nil.
  func setFocusPattern(_ pattern: RoutePattern?) {
    guard focus.routes.count == 1 else { return }
    focus.headsign = pattern?.headsign
    focus.headsignStops = Set(pattern?.stops ?? [])
    if let pattern { focus.direction = pattern.direction }
    focus.fromBus = false
  }

  /// The destinations of a route that the map can show on their own (more than one in the direction).
  func patterns(of route: String, direction: Int) -> [RoutePattern] {
    let all = overlay?.network.patterns(of: route, direction: direction) ?? []
    return all.count > 1 ? all : []
  }

  /// "Westbound": the way a direction of a route runs, in the app's language.
  func directionName(route: String, direction: Int) -> String {
    let name = variants(of: route).first { $0.direction == direction }?.directionName ?? ""
    return name.isEmpty ? L10n.string("Direction \(direction + 1)") : Self.compassName(name)
  }

  /// "D2 · Epic Campus": a destination with its route and pattern number, as the buses show them.
  func patternTitle(_ pattern: RoutePattern) -> String {
    let name = route(pattern.route)?.shortName ?? pattern.route
    let place = pattern.destination.prettyHeadsign
    return pattern.number.map { "\(name)\($0) · \(place)" } ?? place
  }

  /// "Show on map" for an alert: its routes, and the stops its text names, ringed.
  func focusAlert(_ alert: ServiceAlert) {
    let routes = alert.routeIDs.filter { overlay?.routes[$0] != nil }
    guard !routes.isEmpty else { return }
    var next = MapFocus(routes: Set(routes))
    next.highlightedStops = alertStops(alert)
    next.label = alert.header
    next.isAlert = true
    focusReturn = returnTarget()
    focus = next
    sheet = nil
    mode = .map
    fitToFocus()
  }

  /// Rings these buses (late or early) and hides the others.
  func focusBuses(_ buses: [String: BusHighlight], label: String) {
    let routes = Set(buses.keys.compactMap { id in vehicles.first { $0.id == id }?.routeID })
    guard !routes.isEmpty else { return }
    var next = MapFocus(routes: routes)
    next.highlightedBuses = buses
    next.label = label
    focusReturn = returnTarget()
    focus = next
    sheet = nil
    mode = .map
    fitToFocus()
  }

  /// True when the map has something to show for an alert (it names a route).
  func alertCanBeShown(_ alert: ServiceAlert) -> Bool { alert.routeIDs.contains { overlay?.routes[$0] != nil } }

  /// Shows the buses that are running late or early (all routes, or one) and rings them on the map.
  func focusDelays(route: String? = nil, late: Bool = true, early: Bool = false) {
    guard let status else { return }
    var buses: [String: BusHighlight] = [:]
    for row in status.routes where route == nil || row.routeID == route {
      if late { for id in row.lateVehicleIDs { buses[id] = .late } }
      if early { for id in row.earlyVehicleIDs { buses[id] = .early } }
    }
    if buses.isEmpty, let route {
      focusRoute(route)
    } else {
      let label = late && early ? L10n.string("Late and early buses") : (late ? L10n.string("Late buses") : L10n.string("Early buses"))
      focusBuses(buses, label: label)
    }
  }

  /// Stops an alert is about: the ids it lists, plus stop codes written in its text ("stop 1234").
  func alertStops(_ alert: ServiceAlert) -> [String] {
    guard let overlay else { return [] }
    var found = alert.stopIDs.filter { overlay.stops[$0] != nil }
    let byCode = Dictionary(overlay.data.stops.filter { !$0.code.isEmpty }.map { ($0.code, $0.id) }, uniquingKeysWith: { first, _ in first })
    for code in StopCodes.find(in: alert.header + " " + alert.detail) {
      if let id = byCode[code], !found.contains(id) { found.append(id) }
    }
    return found
  }

  /// Zooms the map out to show what is in focus.
  private func fitToFocus() {
    guard let overlay, focus.isActive else { return }
    var points: [Coordinate] = []
    for route in focus.routes { points += overlay.coordinates(route: route, direction: focus.direction) }
    for id in focus.highlightedStops { if let stop = overlay.stops[id] { points.append(Coordinate(latitude: stop.latitude, longitude: stop.longitude)) } }
    for id in focus.highlightedBuses.keys { if let bus = vehicles.first(where: { $0.id == id }) { points.append(Coordinate(latitude: bus.latitude, longitude: bus.longitude)) } }
    if !points.isEmpty { fitRequest = FitRequest(coordinates: points) }
  }

  /// The feed's direction name in the app's language ("Westbound" is "西行き"); other names are shown as the feed has them.
  nonisolated static func compassName(_ name: String) -> String {
    switch name.lowercased() {
    case "eastbound": L10n.string("Eastbound")
    case "westbound": L10n.string("Westbound")
    case "northbound": L10n.string("Northbound")
    case "southbound": L10n.string("Southbound")
    default: name.capitalized
    }
  }

  /// An arrow for the compass direction a route runs in ("Westbound" is an arrow to the left).
  func directionSymbol(route: String, direction: Int) -> String {
    switch variants(of: route).first(where: { $0.direction == direction })?.directionName.lowercased() {
    case "eastbound": "arrow.right"
    case "westbound": "arrow.left"
    case "northbound": "arrow.up"
    case "southbound": "arrow.down"
    default: "arrow.right"
    }
  }

  /// "Westbound to Airport, Epic Campus" for the direction of a route.
  func directionTitle(route: String, direction: Int) -> String {
    guard let variant = variants(of: route).first(where: { $0.direction == direction }) else { return "" }
    let places = variant.headsigns.map(\.prettyHeadsign).joined(separator: ", ")
    let name = Self.compassName(variant.directionName)
    if name.isEmpty { return places }
    return places.isEmpty ? name : L10n.string("\(name) to \(places)")
  }

  func fly(to latitude: Double, _ longitude: Double, minimumZoom: Double) {
    cameraRequest = CameraRequest(latitude: latitude, longitude: longitude, minimumZoom: minimumZoom)
  }

  func locateMe() {
    location.start()
    if let here = location.location {
      fly(to: here.coordinate.latitude, here.coordinate.longitude, minimumZoom: 15)
    }
  }

  private func selectionChanged() {
    showHiddenRoutes = false
    boardEarlier = 0
    boardWindow = Self.defaultBoardWindow
    // Closing a bus sheet releases the line that selecting the bus put on the map, unless the bus waits in the dock.
    if sheet == nil, focus.fromBus, dockedVehicleID == nil { focus = MapFocus() }
    refreshArrivals()
    if sheet?.isDetail == true { ensurePredictions() }  // fresh predictions for what has just opened, then at the rider's pace
    // The vehicle poll is not restarted here: a restart cancels the request under way, and the poll reads what is open (a
    // stop, a bus) by itself on every beat.
  }

  // MARK: Timetable

  private static var cacheURL: URL? {
    try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("mmt_gtfs.zip")
  }

  /// The timetable to start with: the cached download, else the copy bundled with the app, else nothing.
  private func startingZip() -> URL? {
    guard let cache = Self.cacheURL else { return nil }
    if FileManager.default.fileExists(atPath: cache.path) { return cache }
    guard let seed = Bundle.main.url(forResource: "mmt_gtfs", withExtension: "zip") else { return nil }
    try? FileManager.default.copyItem(at: seed, to: cache)
    // Mark the copy as old so that the first launch with a connection fetches a fresh timetable.
    try? FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: cache.path)
    return FileManager.default.fileExists(atPath: cache.path) ? cache : seed
  }

  private func loadSchedule() async {
    do {
      var url = startingZip()
      if url == nil {
        // Nothing local: the first launch needs the network.
        guard await downloadZip(replacingCache: true) else { throw URLError(.notConnectedToInternet) }
        url = Self.cacheURL
      }
      guard let url else { throw URLError(.fileDoesNotExist) }
      try await apply(try await Self.parse(url, current: overlay))
      phase = .ready
      Task { _ = await refreshFromNetwork(force: false) }
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  private struct Parsed {
    let schedule: Schedule
    /// Nil when the drawing the map already has is for this timetable and current.
    let overlay: MapOverlayData?
  }

  /// Parses a timetable, and computes the map's drawing for it unless `current` (the drawing the map has) already fits:
  /// laying out the lanes takes a moment, so it is done once per timetable, not on every launch.
  private static func parse(_ url: URL, current: MapOverlay? = nil) async throws -> Parsed {
    let schedule = try await Task.detached(priority: .userInitiated) { try Schedule.load(zipAt: url) }.value
    if let current, current.feedVersion == schedule.feedVersion, !current.isOutdated {
      return Parsed(schedule: schedule, overlay: nil)
    }
    let overlay = await Task.detached(priority: .utility) { MapOverlayData(schedule: schedule, network: RouteNetwork(schedule: schedule)) }.value
    return Parsed(schedule: schedule, overlay: overlay)
  }

  private func apply(_ parsed: Parsed) async throws {
    schedule = parsed.schedule
    if let data = parsed.overlay {
      overlay = MapOverlay(data)
      Task.detached(priority: .utility) { OverlayStore.save(data) }
    }
    vehicleDirections = directions(of: vehicles)
    vehiclePatterns = patterns(of: vehicles)
    vehicleHeadings = headings(of: vehicles)
    vehicleHeadsigns = headsigns(of: vehicles)
    refreshOutlooks()
    refreshArrivals()
  }

  /// Works out today's service of every route and direction in the background (a few hundred milliseconds in a Release
  /// build); called when the timetable arrives and when a screen that shows it opens.
  func refreshOutlooks() {
    guard let schedule, let overlay else { return }
    let routes = overlay.orderedRoutes.map(\.id)
    Task.detached(priority: .utility) { [weak self] in
      let now = Date()
      var result: [String: ServiceOutlook] = [:]
      for route in routes {
        for direction in [nil, 0, 1] as [Int?] {
          result[Self.outlookKey(route: route, direction: direction)] = schedule.outlook(route: route, direction: direction, at: now)
        }
      }
      await MainActor.run { self?.outlooks = result }
    }
  }

  /// "2" for a destination such as "2-AIRPORT"; nil when the destination has no number in front.
  nonisolated static func pattern(ofHeadsign headsign: String) -> String? {
    guard let dash = headsign.firstIndex(of: "-"), dash != headsign.startIndex else { return nil }
    let head = headsign[..<dash]
    return head.allSatisfy(\.isNumber) ? String(head) : nil
  }

  private func patterns(of vehicles: [VehicleSample]) -> [String: String] {
    guard let schedule else { return [:] }
    var result: [String: String] = [:]
    for vehicle in vehicles {
      if let trip = schedule.trips[vehicle.tripID], let pattern = Self.pattern(ofHeadsign: trip.headsign) { result[vehicle.id] = pattern }
    }
    return result
  }

  /// "E" for a trip the feed calls "Eastbound" (likewise W, N, S; "In" and "Out"); nil for loops, which have one way
  /// round, and for names it does not know.
  nonisolated static func heading(ofDirectionName name: String) -> String? {
    switch name.lowercased() {
    case "eastbound": "E"
    case "westbound": "W"
    case "northbound": "N"
    case "southbound": "S"
    case "inbound": "In"
    case "outbound": "Out"
    default: nil
    }
  }

  private func headsigns(of vehicles: [VehicleSample]) -> [String: String] {
    guard let schedule else { return [:] }
    var result: [String: String] = [:]
    for vehicle in vehicles { if let trip = schedule.trips[vehicle.tripID], !trip.headsign.isEmpty { result[vehicle.id] = trip.headsign } }
    return result
  }

  private func headings(of vehicles: [VehicleSample]) -> [String: String] {
    guard let schedule else { return [:] }
    var result: [String: String] = [:]
    for vehicle in vehicles {
      if let trip = schedule.trips[vehicle.tripID], let heading = Self.heading(ofDirectionName: trip.directionName) { result[vehicle.id] = heading }
    }
    return result
  }

  /// The direction of each bus's trip, from the timetable.
  private func directions(of vehicles: [VehicleSample]) -> [String: Int] {
    guard let schedule else { return [:] }
    var result: [String: Int] = [:]
    for vehicle in vehicles { if let trip = schedule.trips[vehicle.tripID] { result[vehicle.id] = trip.directionID } }
    return result
  }

  /// Fetches the timetable at most once a day (or when `force` is set). The server is asked first whether the file has
  /// changed (it sends an ETag), so a day without a new timetable costs a few hundred bytes instead of 7 MB. A new feed
  /// replaces the loaded one only if its version differs; a failed attempt (offline) changes nothing.
  private func refreshFromNetwork(force: Bool) async -> RefreshResult {
    guard let cache = Self.cacheURL else { return .failed }
    let modified = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    if !force, Date().timeIntervalSince(modified) < 86_400 { return .upToDate }
    var request = URLRequest(url: Self.scheduleURL)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    // The timetable is 7 MB and changes every few weeks: unless the rider allowed mobile data for it, it waits for Wi-Fi, but
    // not when the copy the phone has is no longer valid (a current one matters more than the data) or the rider asked.
    let expired = schedule?.feedEnd.map { $0.value < ServiceDate(Date(), in: schedule?.timeZone ?? .current).value } ?? false
    if settings.values.timetableOnlyOnWiFi, !expired, !force { request.allowsExpensiveNetworkAccess = false }
    let defaults = UserDefaults.standard
    if FileManager.default.fileExists(atPath: cache.path) {
      if let etag = defaults.string(forKey: Self.etagKey) { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
      if let date = defaults.string(forKey: Self.lastModifiedKey) { request.setValue(date, forHTTPHeaderField: "If-Modified-Since") }
    }
    do {
      let (temporary, response) = try await URLSession.shared.download(for: request)
      guard let http = response as? HTTPURLResponse else { return .failed }
      if http.statusCode == 304 {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cache.path)
        return .upToDate
      }
      guard http.statusCode == 200 else { return .failed }
      let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      DataMeter.shared.record(.timetable, bytes: size, metered: NetworkStatus.shared.isMetered)
      let fresh = try await Self.parse(temporary, current: overlay)
      remember(http, in: defaults)
      if fresh.schedule.feedVersion == schedule?.feedVersion {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cache.path)
        return .upToDate
      }
      try? FileManager.default.removeItem(at: cache)
      try FileManager.default.moveItem(at: temporary, to: cache)
      try await apply(fresh)
      return .updated
    } catch {
      return .failed
    }
  }

  private static let etagKey = "timetable.etag"
  private static let lastModifiedKey = "timetable.lastModified"

  /// Keeps what the server said about the file we have, for the next conditional request.
  private func remember(_ response: HTTPURLResponse, in defaults: UserDefaults) {
    defaults.set(response.value(forHTTPHeaderField: "ETag"), forKey: Self.etagKey)
    defaults.set(response.value(forHTTPHeaderField: "Last-Modified"), forKey: Self.lastModifiedKey)
  }

  /// Used only when there is no local copy at all.
  private func downloadZip(replacingCache: Bool) async -> Bool {
    guard let cache = Self.cacheURL else { return false }
    do {
      let (temporary, response) = try await URLSession.shared.download(from: Self.scheduleURL)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
      DataMeter.shared.record(
        .timetable, bytes: (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0, metered: NetworkStatus.shared.isMetered)
      try? FileManager.default.removeItem(at: cache)
      try FileManager.default.moveItem(at: temporary, to: cache)
      remember(http, in: .standard)
      return true
    } catch {
      return false
    }
  }

  // MARK: Live data

  /// Starts the vehicle poll again. It carries on with its schedule (the next request waits for its time) unless
  /// `immediately`: the rider asked for fresh buses, or the app has just come back to the foreground.
  private func restartPolling(immediately: Bool = false, force: Bool = false) {
    pollTask?.cancel()
    guard started else { return }
    // `force`: the rider pressed Refresh, so the app is in front whatever it believes about its state.
    if !force && !isActive && settings.values.pauseLiveInBackground { return }
    if immediately {
      nextPollAt = .distantPast
      pollScheduled = false
    }
    pollTask = Task { [weak self] in await self?.pollLoop() }
  }

  /// Whatever stops the vehicle poll (a request that never comes back, a loop that ended, a state nobody thought of), the rider
  /// must not be left with buses getting older: while the app is in front and nothing has answered for much longer than a
  /// beat, the poll is started again and asks at once.
  private func startWatchdog() {
    Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard let self else { return }
        self.checkPoll()
      }
    }
  }

  private func checkPoll() {
    guard started, isActive || !settings.values.pauseLiveInBackground else { return }
    let now = Date()
    let patience = max(30, Double(settings.values.updateInterval) * 2 + 10)
    let lastAnswer = max(lastLiveUpdate ?? .distantPast, watchdogSince)
    guard now.timeIntervalSince(lastAnswer) > patience, now.timeIntervalSince(lastWatchdogRestart) > patience else { return }
    lastWatchdogRestart = now
    pollLog.error("no answer for \(Int(now.timeIntervalSince(lastAnswer))) s: the poll is started again")
    restartPolling(immediately: true, force: true)
  }

  /// The city rebuilds its feed on a fixed beat (30 s, measured) and each bus reports on the same beat, so asking more
  /// often only returns the same data. After a new feed is seen, the next request waits until just before the next
  /// beat; if the feed has not changed yet, it tries again every 2 seconds. This gives the freshest positions with
  /// about a third of the requests of a fixed 10-second poll. Only local time is used, so a wrong clock on the phone
  /// cannot throw the timing off.
  private func pollLoop() async {
    let wait = nextPollAt.timeIntervalSinceNow
    if wait > 0 {
      try? await Task.sleep(for: .seconds(wait))
      if Task.isCancelled { return }
    }
    while !Task.isCancelled {
      var delay = 10.0
      do {
        let snapshot = try await client.fetch(.vehicles)
        // A feed stamped before the one on screen (a slow server behind the same address) is not news: it would move the
        // buses back.
        let older = snapshot.feedTimestamp.flatMap { new in feedTimestamp.map { new < $0 } } ?? false
        let isNew = !older && (vehicles.isEmpty || snapshot.feedTimestamp == nil || snapshot.feedTimestamp != feedTimestamp)
        if isNew {
          if let old = feedTimestamp, let new = snapshot.feedTimestamp, new > old { notePeriod(new.timeIntervalSince(old)) }
          if let stamp = snapshot.feedTimestamp, let serverNow = snapshot.serverDate {
            let age = serverNow.timeIntervalSince(stamp)
            pollLog.info("new feed: \(Int(age.rounded())) s old, \(self.pollUnchanged + 1) requests, lag estimate \(self.publishLag.estimate, format: .fixed(precision: 1)) s, scheduled \(self.pollScheduled)")
            if pollScheduled { publishLag.note(age: age) }
          }
          pollScheduled = false
          feedTimestamp = snapshot.feedTimestamp
          vehicles = snapshot.vehicles
          vehicleDirections = directions(of: snapshot.vehicles)
          vehiclePatterns = patterns(of: snapshot.vehicles)
          vehicleHeadings = headings(of: snapshot.vehicles)
          vehicleHeadsigns = headsigns(of: snapshot.vehicles)
          offRouteVehicleIDs = computeOffRoute(snapshot.vehicles)
          pollUnchanged = 0
          pollLastChange = Date()
          feedChangedAt = pollLastChange
        } else {
          pollUnchanged += 1
        }
        lastLiveUpdate = Date()
        liveFailing = false
        let fixed = settings.values.updateInterval
        if fixed > 0 {
          delay = Double(fixed)
        } else if isNew, let stamp = snapshot.feedTimestamp, let serverNow = snapshot.serverDate {
          // The next feed is stamped one period after this one. The server's own clock says how far off that is, so the
          // phone's clock does not matter. A feed turns up on the server a few seconds after its stamp (`publishLag`,
          // learned); asking a second before that costs at most one retry, asking much earlier costs several.
          delay = min(45, max(2, stamp.addingTimeInterval(feedPeriod + publishLag.estimate - 1).timeIntervalSince(serverNow)))
          pollScheduled = true
        } else if isNew {
          delay = max(2, pollLastChange.addingTimeInterval(feedPeriod - 1).timeIntervalSinceNow)
        } else {
          delay = pollUnchanged < 8 ? 2 : 10  // the feed is late or stopped: do not hammer the server
        }
        // The large downloads run beside the poll, never in front of it: on a slow connection the positions must not wait.
        if isNew { startSlowData() }
      } catch is CancellationError {
        return
      } catch {
        if Task.isCancelled { return }  // a restart cancels the request; that is not a failure
        liveFailing = true
      }
      refreshArrivals()
      refreshStatus()
      nextPollAt = Date().addingTimeInterval(delay)
      try? await Task.sleep(for: .seconds(delay))
    }
  }

  /// Fetches the alerts and trip predictions, and checks the watched routes, without holding up the vehicle poll. One at
  /// a time: while the last one is still downloading (a slow connection), a new beat starts nothing.
  private func startSlowData() {
    guard !slowDataBusy else { return }
    slowDataBusy = true
    Task { [weak self] in
      guard let self else { return }
      await refreshSlowData()
      await evaluateWatch()
      slowDataBusy = false
      refreshArrivals()
      refreshStatus()
    }
  }

  /// Alerts (about 1 KB, change rarely) and trip predictions (about 160 KB, only needed while a stop, a bus, the service
  /// board or the planner is open) ride along with a new vehicle feed. The predictions are most of the app's data: they
  /// are fetched at most every `predictionInterval`, not with every beat of the vehicle feed.
  private func refreshSlowData() async {
    if Date().timeIntervalSince(lastAlertFetch) > 60 {
      lastAlertFetch = Date()
      if let snapshot = try? await client.fetch(.alerts) { alerts = snapshot.alerts }
    }
    let watching = settings.values.watchEnabled && settings.values.isWatchingAnything
    if sheet?.isDetail == true || mode != .map || watching || needsDelays,
      Date().timeIntervalSince(lastTripsFetch) >= predictionInterval(watching: watching)
    {
      await fetchPredictions()
    }
  }

  /// Fetches the trip updates, unless a fetch is already under way (opening a stop and the poll must not both download them).
  private func fetchPredictions() async {
    guard !fetchingPredictions else { return }
    fetchingPredictions = true
    defer { fetchingPredictions = false }
    if let snapshot = try? await client.fetch(.trips) {
      predictions = snapshot.predictions
      lastTripsFetch = Date()
    }
  }

  /// How old the trip updates may get before they are fetched again, from the rider's choice for the connection they are
  /// on (Settings > Mobile data). Automatic: a stop or bus on screen, the planner and a watched route need them fresh (a
  /// minute); a focused route, a list or the service board only want the counts (two minutes); on mobile data, with "Save
  /// mobile data" on, twice and four times as long (Low Data Mode). Measured before this limit existed: 20 MB an hour with
  /// a stop open, against 2 MB an hour for the positions alone. A few seconds are taken off, because the vehicle feed that
  /// triggers a fetch beats every 30 seconds or more.
  func predictionInterval(watching: Bool) -> TimeInterval {
    let values = settings.values
    let network = NetworkStatus.shared
    let urgent = sheet?.isDetail == true || mode == .plan || watching
    return Self.predictionInterval(
      network.isMetered ? values.predictionsOnMobile : values.predictionsOnWiFi, urgent: urgent,
      slowdown: network.slowdown(saving: values.saveMobileData), watching: watching)
  }

  /// The gap between two fetches for a choice (infinite when nothing is fetched by itself).
  nonisolated static func predictionInterval(_ choice: PredictionRefresh, urgent: Bool, slowdown: Double, watching: Bool) -> TimeInterval {
    switch choice {
    case .automatic: return (urgent ? 60 : 120) * slowdown - 5
    case .manual: return watching ? 295 : .infinity  // a watched route is still checked, every five minutes
    default: return (choice.seconds ?? 60) - 5
    }
  }

  // MARK: Watched routes

  /// Asks for permission to send notifications the first time something is watched; false when it was refused.
  private func allowWatching() async -> Bool {
    if settings.values.watchEnabled { return true }
    guard await WatchNotifier.authorize() else {
      notificationsDenied = true
      return false
    }
    settings.values.watchEnabled = true
    return true
  }

  /// Turns watching of a whole route (every direction and destination) on or off; the first time, asks for permission to
  /// send notifications. Turning it off also lets go of the single destinations chosen on that route.
  func setWatching(route id: String, _ on: Bool) async {
    if on {
      guard await allowWatching() else { return }
      if !settings.values.watchedRoutes.contains(id) { settings.values.watchedRoutes.append(id) }
    } else {
      settings.values.watchedRoutes.removeAll { $0 == id }
      settings.values.watchedLines.removeAll { $0.routeID == id }
    }
  }

  /// Turns watching of one destination of a route on or off.
  func setWatching(line: WatchLine, _ on: Bool) async {
    if on {
      guard await allowWatching() else { return }
      if !settings.values.watchedLines.contains(line) { settings.values.watchedLines.append(line) }
    } else {
      settings.values.watchedLines.removeAll { $0 == line }
    }
  }

  /// True when the route is watched as a whole or in part.
  func isWatching(route id: String) -> Bool {
    settings.values.watchedRoutes.contains(id) || settings.values.watchedLines.contains { $0.routeID == id }
  }

  func isWatchingWhole(route id: String) -> Bool { settings.values.watchedRoutes.contains(id) }

  /// True when this destination is told about, on its own or because the whole route is watched.
  func isWatching(line: WatchLine) -> Bool {
    settings.values.watchedRoutes.contains(line.routeID) || settings.values.watchedLines.contains(line)
  }

  /// Routes and single destinations being watched, for the count in Settings.
  var watchedCount: Int {
    let wholeRoutes = Set(settings.values.watchedRoutes)
    return wholeRoutes.count + settings.values.watchedLines.filter { !wholeRoutes.contains($0.routeID) }.count
  }

  /// Looks at the watched routes with what is known now and notifies about anything new.
  func evaluateWatch() async {
    let prefs = settings.values
    guard prefs.watchEnabled, prefs.isWatchingAnything, let schedule else { return }
    var kinds: Set<WatchKind> = []
    if prefs.watchLate { kinds.insert(.late) }
    if prefs.watchEarly { kinds.insert(.early) }
    if prefs.watchAlerts { kinds.insert(.alert) }
    let now = Date()
    let status = ServiceStatusBuilder.build(schedule: schedule, predictions: predictions, vehicles: vehicles, now: now)
    let events = WatchEvaluator.evaluate(
      status: status, alerts: alerts, now: now, routes: Set(prefs.watchedRoutes), lines: Set(prefs.watchedLines), kinds: kinds,
      lateAfter: Double(prefs.watchLateMinutes) * 60, earlyAfter: Double(prefs.watchEarlyMinutes) * 60)
    await watch.deliver(events, now: now) { [weak self] id in
      guard let self, let route = self.route(id) else { return (id, "8E8E93") }
      // The colour the route badge shows (the quiet palette greys map lines, badges keep the agency colour).
      let palette = self.settings.values.routePalette
      return (route.shortName, RouteColors.fillHex(for: route, palette: palette == .quiet ? .agency : palette, among: self.orderedRoutes))
    }
  }

  /// One check from the background: loads what is needed, looks, and goes back to sleep.
  func runBackgroundWatch() async {
    guard settings.values.watchEnabled, settings.values.isWatchingAnything else { return }
    if schedule == nil, let url = startingZip() { try? await apply(try await Self.parse(url, current: overlay)) }
    guard schedule != nil else { return }
    if let snapshot = try? await client.fetch(.vehicles) { vehicles = snapshot.vehicles }
    if let snapshot = try? await client.fetch(.trips) { predictions = snapshot.predictions }
    if let snapshot = try? await client.fetch(.alerts) { alerts = snapshot.alerts }
    await evaluateWatch()
  }

  /// The feed's rebuild period, learned from the gaps between its timestamps (30 s until seen).
  private func notePeriod(_ seconds: TimeInterval) {
    guard seconds > 5, seconds < 120 else { return }
    periods.append(seconds)
    if periods.count > 9 { periods.removeFirst() }
    feedPeriod = periods.sorted()[periods.count / 2]
  }

  /// Median age of the bus positions on screen, in seconds: how far behind the real buses the map is.
  func positionAge(at now: Date) -> TimeInterval? {
    let ages = vehicles.compactMap { $0.timestamp.map { now.timeIntervalSince($0) } }.sorted()
    guard !ages.isEmpty else { return nil }
    return max(0, ages[ages.count / 2])
  }

  /// Recomputes the service board when it is on screen.
  /// True when something on screen needs to know how late each bus is: the service board, the routes list, a focused
  /// route, a stop or bus sheet, the live-status card.
  private var needsDelays: Bool {
    mode == .info || sheet == .routes || sheet?.isDetail == true || focus.isActive || liveSummaryOpen
  }

  func refreshStatus() {
    guard needsDelays, let schedule else { return }
    let now = Date()
    let built = ServiceStatusBuilder.build(schedule: schedule, predictions: predictions, vehicles: vehicles, now: now)
    status = built
    var delays: [String: Double] = [:]
    for route in built.routes { for delay in route.busDelays { delays[delay.vehicleID] = delay.seconds } }
    if delays != vehicleDelays { vehicleDelays = delays }
    var idle: [String: IdleBus] = [:]
    for vehicle in vehicles where vehicle.tripID.isEmpty {
      idle[vehicle.id] = IdleBus(next: BusNextTrip.of(vehicle, predictions: predictions, schedule: schedule, now: now))
    }
    if idle != idleBuses { idleBuses = idle }
  }

  /// Fetches the trip updates now (when the last ones are over 30 s old), for a screen that has just opened and needs them,
  /// or because the rider asked for fresh data. Whatever the refresh setting says.
  func ensurePredictions() {
    guard Date().timeIntervalSince(lastTripsFetch) > 30 else { return refreshStatus() }
    Task { [weak self] in
      guard let self else { return }
      await fetchPredictions()
      refreshStatus()
      refreshArrivals()
    }
  }

  /// A moving bus more than 150 m from its trip's line is treated as off its usual route. Standing buses (at a terminal
  /// or a stop) are ignored, since they are often parked off the line.
  private func computeOffRoute(_ vehicles: [VehicleSample]) -> Set<String> {
    guard let schedule else { return [] }
    var result: Set<String> = []
    for vehicle in vehicles {
      if let speed = vehicle.speed, speed < 0.5 { continue }
      if let distance = schedule.distanceFromRoute(of: vehicle), distance > 150 { result.insert(vehicle.id) }
    }
    return result
  }

  /// Recomputes the board for the selected stop.
  func refreshArrivals() {
    guard let schedule, let stopID = selectedStopID else {
      if !arrivals.isEmpty { arrivals = [] }
      return
    }
    let now = Date()
    func coming(_ list: [Arrival]) -> Bool { list.contains { !$0.hasGone(at: now) && !$0.isUnconfirmed(at: now) } }
    var found = Arrivals.upcoming(
      schedule: schedule, stopID: stopID, now: now, window: boardWindow, predictions: predictions, vehicles: vehicles,
      limit: boardLimit, earlier: boardEarlier)
    arrivalsAreLater = false
    if !coming(found) {
      // Nothing in the window (late at night): show when service resumes.
      found = Arrivals.upcoming(
        schedule: schedule, stopID: stopID, now: now, window: 30 * 3600, predictions: predictions, vehicles: vehicles, limit: 6,
        earlier: boardEarlier)
      arrivalsAreLater = coming(found)
    }
    arrivals = found
  }

  // MARK: Bus details

  /// Every stop of a bus's trip to the terminal, those it has passed marked.
  func tripStops(of vehicle: VehicleSample, now: Date = Date()) -> [TripStopEta] {
    guard let schedule else { return [] }
    let prediction = predictions.first { $0.tripID == vehicle.tripID }
    return Arrivals.tripStops(
      schedule: schedule, tripID: vehicle.tripID, now: now, prediction: prediction, currentSequence: vehicle.currentStopSequence)
  }

  /// Every stop of a trip no bus is reporting on, with the timetable's times.
  func tripStops(tripID: String, on date: ServiceDate) -> [TripStopEta] {
    guard let schedule else { return [] }
    return Arrivals.tripStops(schedule: schedule, tripID: tripID, now: Date(), prediction: nil, serviceDate: date)
  }

  /// Alerts in force that concern this stop, directly or through a route that serves it.
  func alerts(forStop id: String) -> [ServiceAlert] {
    let routes = Set(visibleRoutes(atStop: id))
    return activeAlerts.filter { alert in
      alert.stopIDs.contains(id) || !routes.isDisjoint(with: alert.routeIDs)
    }
  }

  func alerts(forRoute id: String) -> [ServiceAlert] {
    activeAlerts.filter { $0.routeIDs.contains(id) }
  }

  func headsign(of tripID: String) -> String { schedule?.trips[tripID]?.headsign ?? "" }
}


/// How the buses of a route are doing: how many are on the road, and how many are late (over 5 minutes), on time and
/// early (over 2 minutes). Buses without a prediction count only in the total.
struct FleetBreakdown: Equatable {
  var total = 0
  var late = 0
  var onTime = 0
  var early = 0
  var measured: Int { late + onTime + early }
}

/// A bus that is not on a trip, and the trip it will run next when the trip updates say.
struct IdleBus: Equatable {
  let next: NextTrip?
}
