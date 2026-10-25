import UIKit

/// The small picture on the right of a late or early notification: the route's colour with its name on top, a red band
/// (late) or a blue one (early) underneath with the minutes. Notification text cannot be coloured, a picture can.
enum NotificationBadge {
  /// 40 pt at 3x, the size iOS shows a thumbnail at.
  static let points: CGFloat = 40
  static let scale: CGFloat = 3

  private static let lateRed = UIColor(red: 0xE5 / 255, green: 0x35 / 255, blue: 0x2B / 255, alpha: 1)
  private static let earlyBlue = UIColor(red: 0x2F / 255, green: 0x6F / 255, blue: 0xDB / 255, alpha: 1)

  /// `label` is the route with its pattern number ("D2"), `fillHex` the route's colour as the app's route badge shows it,
  /// `minutes` positive when the bus is late and negative when it is early.
  static func image(label: String, fillHex: String, minutes: Int) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    let side = points
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
      let rect = CGRect(x: 0, y: 0, width: side, height: side)
      UIBezierPath(roundedRect: rect, cornerRadius: side * 0.22).addClip()
      let fill = UIColor(hex: fillHex)
      fill.setFill()
      UIRectFill(rect)
      let band = side * 0.38
      (minutes > 0 ? lateRed : earlyBlue).setFill()
      UIRectFill(CGRect(x: 0, y: side - band, width: side, height: band))
      // A thin light line between the two keeps a red route above a red band two things.
      UIColor(white: 1, alpha: 0.9).setFill()
      UIRectFill(CGRect(x: 0, y: side - band, width: side, height: max(1.0 / scale * 2, side * 0.015)))
      draw(
        label, in: CGRect(x: 0, y: 0, width: side, height: side - band), size: side * (label.count > 2 ? 0.34 : 0.40), weight: .heavy,
        color: RouteColors.text(on: fill))
      draw(
        "\(minutes > 0 ? "+" : "−")\(abs(minutes))", in: CGRect(x: 0, y: side - band, width: side, height: band), size: side * 0.26,
        weight: .bold, color: .white)
    }
  }

  private static func draw(_ text: String, in rect: CGRect, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let string = NSAttributedString(
      string: text, attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    let height = string.size().height
    string.draw(in: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height))
  }

  /// The badge as a PNG file that a notification can carry (the system takes the file over, so it is written fresh each time).
  static func file(label: String, fillHex: String, minutes: Int) -> URL? {
    guard let data = image(label: label, fillHex: fillHex, minutes: minutes).pngData() else { return nil }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("badge-\(UUID().uuidString).png")
    do {
      try data.write(to: url)
      return url
    } catch {
      return nil
    }
  }
}
