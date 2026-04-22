import Foundation
import CoreGraphics
import ImageIO

let data = Data(repeating: 0, count: 10)
let url = URL.documentsDirectory.appendingPathComponent("test.webp")
try! data.write(to: url)
print("File exists: \(FileManager.default.fileExists(atPath: url.path))")
