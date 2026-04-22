import Foundation

let path = "1234.webp"
let filename = (path as NSString).lastPathComponent
let url = URL.documentsDirectory.appendingPathComponent(filename)
print(url.path)
