import SwiftData
import SwiftUI

@main
struct CilantroCheckApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: CheckRecord.self)
    }
}
