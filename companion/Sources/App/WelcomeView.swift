import SwiftUI

/// The first screen: where the library is.
struct WelcomeView: View {
    @Environment(LibraryStore.self) private var store
    @State private var picking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)
                AppMark()
                    .frame(width: 112, height: 112)
                VStack(spacing: 10) {
                    Text("AetherNX Companion")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Your games from AetherNX on the Mac: their saves, mods and cheats, kept in step through iCloud Drive.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 12) {
                    Button {
                        picking = true
                    } label: {
                        Label("Choose the AetherNX Folder", systemImage: "folder.badge.gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button {
                        store.useDemo()
                    } label: {
                        Text("Look at a Demo Library")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(maxWidth: 420)
                VStack(alignment: .leading, spacing: 14) {
                    Step(number: 1, text: "On the Mac, in AetherNX: Settings → General → Cloud saves → iCloud Drive › AetherNX.")
                    Step(number: 2, text: "Here, choose iCloud Drive › AetherNX. Each game you built or installed from the Mac has a folder there.")
                    Step(number: 3, text: "In each game's app, choose that game's folder in Cloud saves, so the save goes through it.")
                }
                .padding(18)
                .frame(maxWidth: 420, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 18))
                Text("The games stay their own apps: iOS lets no app install or run another app's code. This one keeps their folders in order and opens them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.choose(url) }
        }
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: .circle)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The app's mark, drawn: no picture file to ship.
struct AppMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.18, blue: 0.62), Color(red: 0.93, green: 0.42, blue: 0.52)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white)
            Image(systemName: "icloud.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .offset(x: 30, y: -30)
        }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .accessibilityHidden(true)
    }
}
