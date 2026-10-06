import Foundation

/// One route shape to be laid out next to the others that share its streets.
public struct BundleInput: Sendable {
  public let route: String
  /// Position of the route in the route list; lower comes first in a bundle.
  public let order: Int
  public let direction: Int
  public let shapeID: String
  public let points: [Coordinate]

  public init(route: String, order: Int, direction: Int, shapeID: String, points: [Coordinate]) {
    self.route = route
    self.order = order
    self.direction = direction
    self.shapeID = shapeID
    self.points = points
  }
}

/// A stretch of a route's overview line that keeps one lane. Drawn with a sideways offset of `lane` times a spacing, so
/// that routes sharing a street run next to each other, like the bands of a transit diagram.
public struct BundledLine: Sendable, Equatable {
  public let route: String
  /// 0 for a route alone on its street; otherwise steps to the right (positive) or left (negative) of the line's own
  /// direction. Fractional values are the short ramps between two lanes.
  public let lane: Double
  /// How many routes run side by side here (fractional in the ramps between two bundles). The busier the street, the
  /// thinner the lines are drawn, so that a bundle of eleven does not take up half the screen.
  public let crowd: Double
  public let coordinates: [Coordinate]
}

/// A route line in one direction, with its variants (other destinations along nearly the same streets) merged.
public struct DirectionLine: Sendable, Equatable {
  public let route: String
  public let direction: Int
  public let coordinates: [Coordinate]
}

/// Lays out an overview of all routes: one line per route (its directions and variants merged where they run along the
/// same streets) and, where routes share a street, a lane for each, side by side on one shared centre line.
///
/// 1. Each route's shapes are merged: the longest is kept whole, and of the others only the parts more than `merge`
///    metres away from what is kept (a one-way street used in one direction only, a branch). Spikes out to a stop and
///    back are removed first.
/// 2. The lines are laid onto a shared skeleton, route by route: where a line runs within `snap` metres of skeleton that
///    is already there, and roughly parallel to it, it follows that skeleton exactly; elsewhere its own points become new
///    skeleton. Every route on a street therefore follows the very same centre line, so that their lanes are parallel
///    (each feed draws the same street a few metres differently, which made lanes wobble).
/// 3. Each piece of skeleton knows the routes that use it. Each gets a lane by its order in the route list, centred on
///    the street, on the side measured against the skeleton's own direction, so that a route running the other way
///    keeps its side.
/// 4. Lanes are smoothed along each route (no lane kept for less than `minRun` pieces) and a change of lane is spread
///    over `ramp` pieces.
public enum RouteBundler {
  public static func overview(
    _ shapes: [BundleInput], step: Double = 10, merge: Double = 30, snap: Double = 18, minRun: Int = 12, ramp: Int = 6
  ) -> [BundledLine] {
    let all = shapes.flatMap(\.points)
    guard !all.isEmpty else { return [] }
    let frame = Frame(latitude: all.map(\.latitude).reduce(0, +) / Double(all.count))
    let orderOfRoute = Dictionary(shapes.map { ($0.route, $0.order) }, uniquingKeysWith: min)
    func ordered(_ a: String, _ b: String) -> Bool { (orderOfRoute[a] ?? .max, a) < (orderOfRoute[b] ?? .max, b) }

    // 1. One merged set of lines per route.
    let lines = mergedLines(shapes, by: \.route, sortedBy: ordered, frame: frame, step: step, merge: merge)
      .map { (route: $0.group, points: $0.points) }

    // 2. The shared skeleton, and each line as a walk along it.
    var skeleton: [[Point]] = []
    var index = SegmentIndex(cell: max(snap * 2, 40))
    var walks: [(route: String, positions: [Position])] = []
    for line in lines {
      let points = line.points
      var snapped: [Position?] = points.indices.map { i in
        let way = tangent(points, i)
        var best: (position: Position, distance: Double)?
        for hit in index.near(points[i], within: snap) {
          let a = skeleton[hit.line][hit.segment], b = skeleton[hit.line][hit.segment + 1]
          guard abs(dot(way, unit(a, b))) >= parallel else { continue }
          let (t, d) = project(points[i], a, b)
          if best == nil || d < best!.distance { best = (Position(line: hit.line, segment: hit.segment, t: t), d) }
        }
        return best?.position
      }
      // A point or two that does not snap between points that do is noise (a stop a little off the street), and a point
      // or two that snaps between points that do not is a crossing: neither changes what the line does.
      snapped = cleaned(snapped, points: points, skeleton: skeleton, index: index, snap: snap)

      var positions: [Position] = []
      var i = 0
      while i < points.count {
        if let position = snapped[i] {
          positions.append(position)
          i += 1
          continue
        }
        var end = i
        while end < points.count, snapped[end] == nil { end += 1 }
        // A stretch on its own becomes skeleton, joined to the skeleton points before and after it.
        var piece: [Point] = []
        if let before = positions.last { piece.append(location(before, skeleton)) }
        piece += points[i..<end]
        if end < points.count, let after = snapped[end] { piece.append(location(after, skeleton)) }
        let id = skeleton.count
        skeleton.append(piece)
        index.insert(piece, line: id)
        let first = positions.isEmpty ? 0 : 1
        for vertex in first..<(first + (end - i)) {
          positions.append(Position(line: id, segment: min(vertex, piece.count - 2), t: vertex == piece.count - 1 ? 1 : 0))
        }
        i = end
      }
      walks.append((line.route, positions))
    }

    // 3. Each route's pieces on the skeleton, then the order of routes wherever they run side by side.
    struct Piece {
      var from: Point
      var to: Point
      var key: Int?  // skeleton line << 32 | segment; nil for a short link between two skeleton lines
      var sign: Double  // 1 along the skeleton line, -1 against it
    }
    var routePieces: [(route: String, pieces: [Piece])] = []
    for walk in walks {
      var pieces: [Piece] = []
      for (p, q) in zip(walk.positions, walk.positions.dropFirst()) {
        guard p.line == q.line else {
          pieces.append(Piece(from: location(p, skeleton), to: location(q, skeleton), key: nil, sign: 1))
          continue
        }
        let line = skeleton[p.line]
        let forward = (q.segment, q.t) >= (p.segment, p.t)
        var stops: [(point: Point, segment: Int)] = [(location(p, skeleton), p.segment)]
        if forward {
          if q.segment > p.segment { for vertex in (p.segment + 1)...q.segment { stops.append((line[vertex], vertex)) } }
        } else if p.segment > q.segment {
          for vertex in stride(from: p.segment, through: q.segment + 1, by: -1) { stops.append((line[vertex], vertex - 1)) }
        }
        stops.append((location(q, skeleton), q.segment))
        for (a, b) in zip(stops, stops.dropFirst()) where distance(a.point, b.point) > 0.01 {
          let segment = forward ? a.segment : b.segment
          pieces.append(Piece(from: a.point, to: b.point, key: p.line << 32 | segment, sign: forward ? 1 : -1))
        }
      }
      routePieces.append((walk.route, pieces))
    }

    // The frame of each skeleton line: which way its lanes are counted. Lines that continue each other (a route goes
    // from one to the next without turning sharply) share one frame, so the order of routes carries on unbroken along
    // a street, even where the street curves or is made of several lines. Sharp turns start a new frame.
    var votes: [Int: [Int: Double]] = [:]  // line -> neighbour line -> sum of (relation) over routes
    for (_, pieces) in routePieces {
      var previous: (line: Int, sign: Double, heading: Point)?
      for piece in pieces {
        guard let key = piece.key else { continue }
        let line = key >> 32, heading = unit(piece.from, piece.to)
        if let before = previous, before.line != line, dot(before.heading, heading) > cos(35.0 * .pi / 180) {
          // Same travel frame on both: frame(line) * sign is the same, so the frames differ by the product of signs.
          let relation = before.sign * piece.sign
          votes[before.line, default: [:]][line, default: 0] += relation
          votes[line, default: [:]][before.line, default: 0] += relation
        }
        previous = (line, piece.sign, heading)
      }
    }
    var lineFrame: [Int: Double] = [:]
    for start in votes.keys.sorted() where lineFrame[start] == nil {
      lineFrame[start] = 1
      var queue = [start]
      var head = 0
      while head < queue.count {
        let current = queue[head]
        head += 1
        let neighbours = (votes[current] ?? [:]).sorted { $0.key < $1.key }
        for (neighbour, relation) in neighbours where lineFrame[neighbour] == nil && relation != 0 {
          lineFrame[neighbour] = lineFrame[current]! * (relation > 0 ? 1 : -1)
          queue.append(neighbour)
        }
      }
    }
    func orientation(_ key: Int) -> Double { lineFrame[key >> 32] ?? 1 }

    // The order of routes in a bundle is decided per pair, once for each stretch the two run side by side: where they
    // part, the one that goes left is on the left and the one that goes right on the right; if they part the same way,
    // the same is looked at where they met; if there is nothing to tell, the route list decides. A stretch has one
    // answer from end to end, so two routes cross only where one of them joins or leaves.
    let count = routePieces.count
    let firstIndex: [[Int: Int]] = routePieces.map { entry in
      var map: [Int: Int] = [:]
      for (index, piece) in entry.pieces.enumerated() { if let key = piece.key, map[key] == nil { map[key] = index } }
      return map
    }
    func angle(_ from: Point, _ to: Point) -> Double { atan2(from.x * to.y - from.y * to.x, dot(from, to)) }
    /// The point `meters` along a walk, from the end of piece `index` going on or from its start going back.
    func along(_ pieces: [Piece], _ index: Int, forward: Bool, meters: Double) -> Point? {
      var remaining = meters
      var last = forward ? pieces[index].to : pieces[index].from
      var k = forward ? index + 1 : index - 1
      while k >= 0, k < pieces.count {
        let a = forward ? pieces[k].from : pieces[k].to, b = forward ? pieces[k].to : pieces[k].from
        let length = distance(a, b)
        if length >= remaining { return lerp(a, b, remaining / max(length, 1e-9)) }
        remaining -= length
        last = b
        k += forward ? 1 : -1
      }
      return meters - remaining >= 10 ? last : nil
    }
    /// 1 when route x is on the left of route y (as seen along x's way) over the stretch `xs` of x against `ys` of y
    /// (y's walk runs the same way as x's when `d` is 1, the opposite way when it is -1); nil when undecided.
    func decide(_ px: [Piece], _ xs: ClosedRange<Int>, _ py: [Piece], _ ys: ClosedRange<Int>, _ d: Int) -> Double? {
      let tolerance = 20.0 * .pi / 180
      // Where they part, going on.
      let endX = px[xs.upperBound].to
      let yEnd = d > 0 ? ys.upperBound : ys.lowerBound
      if let backX = along(px, xs.upperBound, forward: false, meters: 20), let outX = along(px, xs.upperBound, forward: true, meters: 30),
        let outY = along(py, yEnd, forward: d > 0, meters: 30)
      {
        let h = unit(backX, endX)
        let ax = angle(h, unit(endX, outX)), ay = angle(h, unit(endX, outY))
        if abs(ax - ay) > tolerance { return ax > ay ? 1 : -1 }
      }
      // Where they met, looking back.
      let startX = px[xs.lowerBound].from
      let yStart = d > 0 ? ys.lowerBound : ys.upperBound
      if let aheadX = along(px, xs.lowerBound, forward: true, meters: 20), let outX = along(px, xs.lowerBound, forward: false, meters: 30),
        let outY = along(py, yStart, forward: d < 0, meters: 30)
      {
        let hb = unit(aheadX, startX)  // pointing back, away from the stretch
        let ax = angle(hb, unit(startX, outX)), ay = angle(hb, unit(startX, outY))
        if abs(ax - ay) > tolerance { return ax < ay ? 1 : -1 }
      }
      return nil
    }
    var decisions: [Int: [Int: Double]] = [:]  // skeleton piece -> (x * count + y) -> 1 when x is on the left of y
    for x in 0..<count {
      let px = routePieces[x].pieces
      for y in (x + 1)..<max(x + 1, count) {
        let py = routePieces[y].pieces
        let indexInY = firstIndex[y]
        var i = 0
        while i < px.count {
          guard let key = px[i].key, let j0 = indexInY[key] else {
            i += 1
            continue
          }
          let d = px[i].sign == py[j0].sign ? 1 : -1
          var last = i
          while last + 1 < px.count, let next = px[last + 1].key {
            let j = j0 + d * (last + 1 - i)
            guard j >= 0, j < py.count, py[j].key == next else { break }
            last += 1
          }
          let jEnd = j0 + d * (last - i)
          let ys = min(j0, jEnd)...max(j0, jEnd)
          if let left = decide(px, i...last, py, ys, d) {
            for t in i...last { if let k = px[t].key { decisions[k, default: [:]][x * count + y] = left } }
          }
          i = last + 1
        }
      }
    }
    /// The lane of each route on a piece of skeleton, counted to the right of the line's frame.
    var laneCache: [Int: [Int: Double]] = [:]
    func lanes(_ key: Int) -> [Int: Double] {
      if let cached = laneCache[key] { return cached }
      let members = (0..<count).filter { firstIndex[$0][key] != nil }
      let f = orientation(key)
      func leftOf(_ p: Int, _ q: Int) -> Bool {
        if p > q { return !leftOf(q, p) }
        guard let value = decisions[key]?[p * count + q] else { return true }  // undecided: the route list decides
        let along = routePieces[p].pieces[firstIndex[p][key]!].sign * f  // 1 when p runs the way the frame points
        return (value > 0) == (along > 0)
      }
      var score: [Int: Int] = [:]
      for p in members { score[p] = members.filter { $0 != p && leftOf(p, $0) }.count }
      let order = members.sorted { (-score[$0]!, $0) < (-score[$1]!, $1) }
      var result: [Int: Double] = [:]
      for (rank, member) in order.enumerated() { result[member] = Double(rank) - Double(order.count - 1) / 2 }
      laneCache[key] = result
      return result
    }

    // 4. Lanes, smoothed, eased from one to the next, and cut into runs.
    var result: [BundledLine] = []
    for (routeIndex, (route, pieces)) in routePieces.enumerated() where !pieces.isEmpty {
      var values: [Double] = []
      for piece in pieces {
        guard let key = piece.key, let lane = lanes(key)[routeIndex] else {
          values.append(values.last ?? 0)
          continue
        }
        // The lane is counted to the right of the frame of the street; along the route it is to the right only when
        // the route travels the way the frame points.
        values.append(lane * piece.sign * orientation(key))
      }
      let target = stable(values, minRun: minRun)
      // How many routes share the street, for the thickness of the lines.
      var crowds: [Double] = []
      for piece in pieces { crowds.append(piece.key.map { Double(lanes($0).count) } ?? crowds.last ?? 1) }
      let crowdTarget = stable(crowds, minRun: minRun)

      // A change of lane is a slide, never a jump. Each change is spread over enough pieces for its size (at least `ramp`,
      // and about four pieces per lane), and the slide is put on the nearest straight stretch: near a turn it would draw
      // hooks, so it starts a little before or after the point where the bundle really changes. Each piece then has a
      // lane at its start and at its end, and is cut into `split` small steps.
      let split = 4
      let headings = pieces.map { unit($0.from, $0.to) }
      func straight(_ start: Int, _ count: Int) -> Bool {
        let low = max(1, start - 1), high = min(pieces.count - 1, start + count)
        guard low <= high else { return true }
        for k in low...high where dot(headings[k], headings[k - 1]) < cos(20.0 * .pi / 180) { return false }
        return true
      }
      var laneStart = target, laneEnd = target
      var crowdStart = crowdTarget, crowdEnd = crowdTarget
      var changes: [Int] = []
      for k in 1..<max(1, pieces.count) where target[k] != target[k - 1] || crowdTarget[k] != crowdTarget[k - 1] { changes.append(k) }
      var floor = 0  // pieces before this belong to an earlier slide
      for (n, c) in changes.enumerated() {
        let a = target[c - 1], b = target[c]
        let ca = crowdTarget[c - 1], cb = crowdTarget[c]
        let ceiling = n + 1 < changes.count ? changes[n + 1] : pieces.count
        var length = min(40, max(ramp, Int((max(abs(b - a), abs(cb - ca) / 2) * 4).rounded(.up))))
        length = min(length, ceiling - floor)
        var chosen: Int?
        if length >= 1 {
          for distance in 0...30 {
            for start in distance == 0 ? [c] : [c - distance, c + distance] where start >= floor && start + length <= ceiling {
              if straight(start, length) {
                chosen = start
                break
              }
            }
            if chosen != nil { break }
          }
        }
        guard let start = chosen else {
          floor = c  // no straight stretch near: the change stays a step
          continue
        }
        for k in floor..<ceiling {
          if k < start {
            laneStart[k] = a
            laneEnd[k] = a
            crowdStart[k] = ca
            crowdEnd[k] = ca
          } else if k < start + length {
            let t0 = Double(k - start) / Double(length), t1 = Double(k - start + 1) / Double(length)
            laneStart[k] = a + (b - a) * t0
            laneEnd[k] = a + (b - a) * t1
            crowdStart[k] = ca + (cb - ca) * t0
            crowdEnd[k] = ca + (cb - ca) * t1
          } else {
            laneStart[k] = b
            laneEnd[k] = b
            crowdStart[k] = cb
            crowdEnd[k] = cb
          }
        }
        floor = start + length
      }

      var drawn: [(from: Point, to: Point, lane: Double, crowd: Double)] = []
      for (k, piece) in pieces.enumerated() {
        if laneStart[k] == laneEnd[k], crowdStart[k] == crowdEnd[k] {
          drawn.append((piece.from, piece.to, laneStart[k], crowdStart[k]))
          continue
        }
        // A slide goes in steps of an eighth of a lane and one route, so that neighbouring small steps join into one
        // piece: without that a 60 m slide is 24 pieces of 2.5 m, and a city of them is 90 000 pieces to draw.
        for part in 0..<split {
          let from = lerp(piece.from, piece.to, Double(part) / Double(split))
          let to = lerp(piece.from, piece.to, Double(part + 1) / Double(split))
          let t = (Double(part) + 0.5) / Double(split)
          let lane = ((laneStart[k] + (laneEnd[k] - laneStart[k]) * t) * 8).rounded() / 8
          drawn.append((from, to, lane, (crowdStart[k] + (crowdEnd[k] - crowdStart[k]) * t).rounded()))
        }
      }

      var start = 0
      for position in 1...drawn.count {
        if position == drawn.count || drawn[position].lane != drawn[start].lane || drawn[position].crowd != drawn[start].crowd {
          var points = [drawn[start].from]
          for piece in drawn[start..<position] { points.append(piece.to) }
          result.append(
            BundledLine(route: route, lane: drawn[start].lane, crowd: drawn[start].crowd, coordinates: dedupe(points).map(frame.coordinate)))
          start = position
        }
      }
    }
    return result.filter { $0.coordinates.count > 1 }
  }

  private static func lerp(_ a: Point, _ b: Point, _ t: Double) -> Point { Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }

  /// A place on the skeleton: on `segment` of skeleton line `line`, `t` of the way along it.
  struct Position {
    var line: Int
    var segment: Int
    var t: Double
  }

  private static func location(_ position: Position, _ skeleton: [[Point]]) -> Point {
    let a = skeleton[position.line][position.segment], b = skeleton[position.line][position.segment + 1]
    return Point(x: a.x + (b.x - a.x) * position.t, y: a.y + (b.y - a.y) * position.t)
  }

  /// Where `p` falls on the segment from `a` to `b` (0...1), and how far it is from it.
  private static func project(_ p: Point, _ a: Point, _ b: Point) -> (t: Double, distance: Double) {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return (0, distance(p, a)) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
    return (t, distance(p, Point(x: a.x + t * dx, y: a.y + t * dy)))
  }

  /// The direction of a line at point `i`, from its neighbours.
  private static func tangent(_ points: [Point], _ i: Int) -> Point {
    unit(points[max(0, i - 1)], points[min(points.count - 1, i + 1)])
  }

  /// Short gaps in snapping are filled, and short snapped blips are dropped.
  ///
  /// A gap of up to 8 points (about 80 m) between two points on the same skeleton line is a bus bay or a loop into a
  /// stop: the line simply follows the skeleton there. Other gaps of up to 3 points are filled from a little farther
  /// away. A snapped blip of up to 3 points between unsnapped ones is a crossing street, not a shared one.
  private static func cleaned(_ snapped: [Position?], points: [Point], skeleton: [[Point]], index: SegmentIndex, snap: Double) -> [Position?] {
    var result = snapped
    var i = 0
    while i < result.count {
      let isSnapped = result[i] != nil
      var end = i
      while end < result.count, (result[end] != nil) == isSnapped { end += 1 }
      let inside = i > 0 && end < result.count
      if inside, isSnapped, end - i <= 3 {
        for k in i..<end { result[k] = nil }
      } else if inside, !isSnapped, let before = result[i - 1], let after = result[end], before.line == after.line, end - i <= 8 {
        let line = skeleton[before.line]
        let low = min(before.segment, after.segment), high = max(before.segment, after.segment)
        for k in i..<end {
          var best: (position: Position, distance: Double)?
          for segment in low...high {
            let (t, d) = project(points[k], line[segment], line[segment + 1])
            if best == nil || d < best!.distance { best = (Position(line: before.line, segment: segment, t: t), d) }
          }
          if let best, best.distance <= 50 { result[k] = best.position }
        }
      } else if inside, !isSnapped, end - i <= 3 {
        for k in i..<end {
          let way = tangent(points, k)
          var best: (position: Position, distance: Double)?
          for hit in index.near(points[k], within: snap * 1.7) {
            let a = skeleton[hit.line][hit.segment], b = skeleton[hit.line][hit.segment + 1]
            guard abs(dot(way, unit(a, b))) >= parallel else { continue }
            let (t, d) = project(points[k], a, b)
            if d <= snap * 1.7, best == nil || d < best!.distance { best = (Position(line: hit.line, segment: hit.segment, t: t), d) }
          }
          if let best { result[k] = best.position }
        }
      }
      i = end
    }
    return result
  }

  private static func dedupe(_ points: [Point]) -> [Point] {
    var result: [Point] = []
    for point in points where result.last.map({ distance($0, point) > 0.01 }) ?? true { result.append(point) }
    return result
  }

  /// Shapes of the same group merged into lines: the longest is kept whole, and of the others only the parts more than
  /// `merge` metres away from what is kept (a one-way street used in one direction only, a branch). Spikes out to a
  /// stop and back are removed first. A branch starts and ends on the kept line.
  private static func mergedLines(
    _ shapes: [BundleInput], by group: (BundleInput) -> String, sortedBy ordered: (String, String) -> Bool, frame: Frame,
    step: Double, merge: Double
  ) -> [(group: String, points: [Point])] {
    var lines: [(group: String, points: [Point])] = []
    let byGroup = Dictionary(grouping: shapes, by: group)
    for name in byGroup.keys.sorted(by: ordered) {
      let candidates = byGroup[name]!
        .map { despike($0.points.map(frame.point)) }
        .map { densify($0, step: step) }
        .filter { $0.count > 1 }
        .sorted { length($0) > length($1) }
      var kept = SegmentIndex(cell: merge * 2)
      /// The point of the kept lines nearest to `p`, within `merge`: where a branch leaves the main line.
      func nearestOnKept(_ p: Point) -> Point? {
        var best: (point: Point, distance: Double)?
        for hit in kept.near(p, within: merge) {
          let a = lines[hit.line].points[hit.segment], b = lines[hit.line].points[hit.segment + 1]
          let (t, d) = project(p, a, b)
          if best == nil || d < best!.distance { best = (lerp(a, b, t), d) }
        }
        return best?.point
      }
      for points in candidates {
        if kept.isEmpty {
          kept.insert(points, line: lines.count)
          lines.append((name, points))
          continue
        }
        let covered = points.map { kept.nearest($0, within: merge) != nil }
        var index = 0
        while index < points.count {
          guard !covered[index] else {
            index += 1
            continue
          }
          var end = index
          while end < points.count, !covered[end] { end += 1 }
          // Its first and last points lie next to the kept line but up to `merge` away from it, so a short connector runs
          // from the line to them. Without it the branch would stop short, and the route would seem to jump where its
          // two directions part.
          var run = Array(points[max(0, index - 1)..<min(points.count, end + 1)])
          if index > 0, let join = nearestOnKept(points[index - 1]) { run.insert(join, at: 0) }
          if end < points.count, let join = nearestOnKept(points[end]) { run.append(join) }
          if run.count > 1, length(run) >= 60 {
            kept.insert(run, line: lines.count)
            lines.append((name, run))
          }
          index = end
        }
      }
    }
    return lines
  }

  /// One line per route and direction, with the variants of a direction (other destinations along nearly the same
  /// streets) merged into it: what is drawn when a route is looked at on its own.
  public static func directionLines(_ shapes: [BundleInput], step: Double = 10, merge: Double = 12) -> [DirectionLine] {
    let all = shapes.flatMap(\.points)
    guard !all.isEmpty else { return [] }
    let frame = Frame(latitude: all.map(\.latitude).reduce(0, +) / Double(all.count))
    let orderOfRoute = Dictionary(shapes.map { ($0.route, $0.order) }, uniquingKeysWith: min)
    func ordered(_ a: String, _ b: String) -> Bool {
      let ra = a.split(separator: "|")[0], rb = b.split(separator: "|")[0]
      return (orderOfRoute[String(ra)] ?? .max, a) < (orderOfRoute[String(rb)] ?? .max, b)
    }
    return mergedLines(shapes, by: { "\($0.route)|\($0.direction)" }, sortedBy: ordered, frame: frame, step: step, merge: merge).map {
      let parts = $0.group.split(separator: "|")
      return DirectionLine(route: String(parts[0]), direction: Int(parts[1]) ?? 0, coordinates: $0.points.map(frame.coordinate))
    }
  }

  // MARK: Smoothing

  /// The most common value within `radius` places on either side (ties keep the value itself).
  static func majority(_ values: [Double], radius: Int) -> [Double] {
    values.indices.map { index in
      var counts: [Double: Int] = [:]
      for other in max(0, index - radius)...min(values.count - 1, index + radius) { counts[values[other], default: 0] += 1 }
      let best = counts.values.max() ?? 0
      return counts[values[index]] == best ? values[index] : counts.first { $0.value == best }!.key
    }
  }

  /// Joins runs shorter than `minRun` to the longer of their neighbours, so that a lane never lasts only a few metres.
  /// Runs in the middle of a line go first; a short run at an end is only joined when nothing else is left to do.
  static func stable(_ values: [Double], minRun: Int) -> [Double] {
    var values = values
    for _ in 0..<values.count {
      var runs: [(value: Double, start: Int, count: Int)] = []
      for (index, value) in values.enumerated() {
        if let last = runs.last, last.value == value { runs[runs.count - 1].count += 1 } else { runs.append((value, index, 1)) }
      }
      guard runs.count > 1 else { break }
      let short = runs.indices.filter { runs[$0].count < minRun }
      let inside = short.filter { $0 > 0 && $0 < runs.count - 1 }
      guard let pick = (inside.isEmpty ? short : inside).min(by: { runs[$0].count < runs[$1].count }) else { break }
      let before = pick > 0 ? runs[pick - 1] : nil
      let after = pick < runs.count - 1 ? runs[pick + 1] : nil
      let fill = (before?.count ?? -1) >= (after?.count ?? -1) ? before!.value : after!.value
      for index in runs[pick].start..<(runs[pick].start + runs[pick].count) { values[index] = fill }
    }
    return values
  }

  /// Spreads every change of lane over the next `steps` places, in equal parts.
  static func ramped(_ values: [Double], steps: Int) -> [Double] {
    guard steps > 0, values.count > 1 else { return values }
    var result = values
    for index in 1..<values.count where values[index] != values[index - 1] {
      let from = values[index - 1], to = values[index]
      for step in 0..<steps where index + step < values.count && values[index + step] == to {
        result[index + step] = from + (to - from) * Double(step + 1) / Double(steps + 1)
      }
    }
    return result
  }

  // MARK: Geometry in metres

  struct Point: Equatable {
    var x: Double
    var y: Double
  }

  /// A flat frame in metres around the area's mean latitude, good enough for a city.
  private struct Frame {
    let scaleX: Double
    let scaleY = 111_320.0
    init(latitude: Double) { scaleX = 111_320 * cos(latitude * .pi / 180) }
    func point(_ c: Coordinate) -> Point { Point(x: c.longitude * scaleX, y: c.latitude * scaleY) }
    func coordinate(_ p: Point) -> Coordinate { Coordinate(latitude: p.y / scaleY, longitude: p.x / scaleX) }
  }

  private static let parallel = cos(30.0 * Double.pi / 180)

  private static func distance(_ a: Point, _ b: Point) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }
  private static func midpoint(_ a: Point, _ b: Point) -> Point { Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
  private static func dot(_ a: Point, _ b: Point) -> Double { a.x * b.x + a.y * b.y }
  private static func unit(_ a: Point, _ b: Point) -> Point {
    let d = distance(a, b)
    return d > 0 ? Point(x: (b.x - a.x) / d, y: (b.y - a.y) / d) : Point(x: 0, y: 0)
  }
  private static func length(_ points: [Point]) -> Double {
    zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
  }

  static func distance(from p: Point, toSegment a: Point, _ b: Point) -> Double {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return distance(p, a) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
    return distance(p, Point(x: a.x + t * dx, y: a.y + t * dy))
  }

  /// Drops the points that lie within `tolerance` metres of the line between the points kept (Douglas-Peucker), keeping
  /// both ends. Shapes have a point every few metres, most of them on straight streets.
  public static func simplified(_ coordinates: [Coordinate], tolerance: Double) -> [Coordinate] {
    guard coordinates.count > 2 else { return coordinates }
    let frame = Frame(latitude: coordinates[0].latitude)
    let points = coordinates.map(frame.point)
    var keep = [Bool](repeating: false, count: points.count)
    keep[0] = true
    keep[points.count - 1] = true
    var work = [(0, points.count - 1)]
    while let (first, last) = work.popLast() {
      guard last - first > 1 else { continue }
      var far = first, farthest = 0.0
      for index in (first + 1)..<last {
        let d = distance(from: points[index], toSegment: points[first], points[last])
        if d > farthest { (far, farthest) = (index, d) }
      }
      if farthest > tolerance {
        keep[far] = true
        work.append((first, far))
        work.append((far, last))
      }
    }
    return zip(coordinates, keep).filter(\.1).map(\.0)
  }

  /// Removes short excursions that go out and come back, such as a shape that steps aside to a stop.
  static func despike(_ points: [Point]) -> [Point] {
    var points = points.reduce(into: [Point]()) { if $0.last != $1 { $0.append($1) } }
    var changed = true
    while changed, points.count > 2 {
      changed = false
      var index = 1
      while index < points.count - 1 {
        let a = points[index - 1], b = points[index], c = points[index + 1]
        let out = distance(a, b) + distance(b, c)
        if out < 150, distance(a, c) < 0.25 * out {
          points.remove(at: index)
          changed = true
        } else {
          index += 1
        }
      }
    }
    return points
  }

  static func densify(_ points: [Point], step: Double) -> [Point] {
    guard let first = points.first else { return [] }
    var result = [first]
    for (a, b) in zip(points, points.dropFirst()) {
      let pieces = max(1, Int((distance(a, b) / step).rounded(.up)))
      for piece in 1...pieces {
        let t = Double(piece) / Double(pieces)
        result.append(Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
      }
    }
    return result
  }

  /// Segments of lines in a grid, to find the ones near a point quickly.
  struct SegmentIndex {
    let cell: Double
    private var cells: [Int64: [(line: Int, segment: Int, a: Point, b: Point)]] = [:]

    init(cell: Double) { self.cell = cell }

    var isEmpty: Bool { cells.isEmpty }

    private func key(_ x: Int, _ y: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: y))) }

    mutating func insert(_ points: [Point], line: Int) {
      for segment in 0..<(points.count - 1) {
        let a = points[segment], b = points[segment + 1]
        let x0 = Int((min(a.x, b.x) / cell).rounded(.down)), x1 = Int((max(a.x, b.x) / cell).rounded(.down))
        let y0 = Int((min(a.y, b.y) / cell).rounded(.down)), y1 = Int((max(a.y, b.y) / cell).rounded(.down))
        for x in x0...x1 { for y in y0...y1 { cells[key(x, y), default: []].append((line, segment, a, b)) } }
      }
    }

    /// Segments within `radius` of `p` (`radius` must not exceed the cell size).
    func near(_ p: Point, within radius: Double) -> [(line: Int, segment: Int)] {
      let cx = Int((p.x / cell).rounded(.down)), cy = Int((p.y / cell).rounded(.down))
      var found: [(line: Int, segment: Int)] = []
      for x in (cx - 1)...(cx + 1) {
        for y in (cy - 1)...(cy + 1) {
          for item in cells[key(x, y)] ?? [] where RouteBundler.distance(from: p, toSegment: item.a, item.b) <= radius {
            found.append((item.line, item.segment))
          }
        }
      }
      return found
    }

    func nearest(_ p: Point, within radius: Double) -> (line: Int, segment: Int)? { near(p, within: radius).first }
  }
}
