import UIKit

@MainActor
enum TicketingHandoff {
    enum Target {
        case leapTopUp, tfiGo

        var appURL: URL? {
            switch self {
            case .leapTopUp: URL(string: "leaptopup://")
            case .tfiGo: URL(string: "tfigo://")
            }
        }

        var webURL: URL {
            switch self {
            case .leapTopUp: URL(string: "https://www.leapcard.ie")!
            case .tfiGo: URL(string: "https://www.transportforireland.ie")!
            }
        }
    }

    static func open(_ target: Target) {
        let app = UIApplication.shared
        if let url = target.appURL, app.canOpenURL(url) {
            app.open(url)
        } else {
            app.open(target.webURL)
        }
    }
}
