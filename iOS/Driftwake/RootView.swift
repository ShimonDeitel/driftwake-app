import SwiftUI

struct RootView: View {
    @AppStorage("driftwake.theme") private var themeRaw = AppTheme.system.rawValue

    var body: some View {
        MainView()
            .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
            .tint(DriftwakeColor.ember)
    }
}
