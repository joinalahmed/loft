import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "dev.joinal.loft", category: "app")
    static let music = Logger(subsystem: "dev.joinal.loft", category: "music")
    static let hud = Logger(subsystem: "dev.joinal.loft", category: "hud")
    static let api = Logger(subsystem: "dev.joinal.loft", category: "api")
}
