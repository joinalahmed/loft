import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "dev.joinal.isla", category: "app")
    static let music = Logger(subsystem: "dev.joinal.isla", category: "music")
    static let hud = Logger(subsystem: "dev.joinal.isla", category: "hud")
    static let api = Logger(subsystem: "dev.joinal.isla", category: "api")
}
