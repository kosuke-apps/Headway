import Testing
import UIKit

@testable import Headway

@Suite struct NotificationBadgeTests {
  /// The colour of the pixel at (x, y) of the image, in 0...255.
  private func pixel(_ image: UIImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let cg = image.cgImage!
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
    return (Int(data[0]), Int(data[1]), Int(data[2]), Int(data[3]))
  }

  @Test func theBadgeIs120PixelsSquare() {
    let image = NotificationBadge.image(label: "C2", fillHex: "333366", minutes: 13)
    #expect(image.cgImage?.width == 120 && image.cgImage?.height == 120)
  }

  @Test func theBandIsRedWhenLateAndBlueWhenEarly() {
    let late = pixel(NotificationBadge.image(label: "C2", fillHex: "333366", minutes: 13), 22, 100)
    #expect(late.r > 200 && late.g < 90 && late.b < 90)
    let early = pixel(NotificationBadge.image(label: "C2", fillHex: "333366", minutes: -3), 22, 100)
    #expect(early.b > 180 && early.r < 90)
  }

  @Test func theTopIsTheRoutesOwnColour() {
    let top = pixel(NotificationBadge.image(label: "C2", fillHex: "333366", minutes: 13), 10, 30)
    #expect(abs(top.r - 0x33) < 6 && abs(top.g - 0x33) < 6 && abs(top.b - 0x66) < 6)
  }

  @Test func theBadgeCanBeWrittenAsAFile() throws {
    let url = try #require(NotificationBadge.file(label: "D2", fillHex: "333366", minutes: -3))
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(url.pathExtension == "png")
    #expect(try Data(contentsOf: url).count > 100)
  }
}
