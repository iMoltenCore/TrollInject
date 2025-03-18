import Foundation

@objc public class Greeter: NSObject {
    @objc public static func copyAndSignDylib(_ bundleID: URL, target: [URL]) -> [URL] {
        do {
            let injector = try InjectorV3(bundleID)
            return try injector.copyAndSign(target)
        } catch {
            return []
        }
    }
}

