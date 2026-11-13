import SwiftUI

/// The Activity page: the job under way, and everything the app's commands wrote.
struct ActivityPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let job = model.job {
                JobCard(job: job, showsGameName: job.gameID.flatMap { id in model.games.first { $0.id == id }?.name })
                    .padding(16)
                Divider()
            } else if !model.buildQueue.isEmpty {
                BuildQueueList()
                    .padding(16)
                Divider()
            }
            ActivityView()
        }
        .navigationTitle("Activity")
    }
}

/// The Devices page: the iPhones and iPads paired with this Mac, what this Mac installed on each, and how it signs and installs.
struct DevicesPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.layoutWidth) private var layoutWidth

    var body: some View {
        Group {
            if layoutWidth == .wide {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { devices.padding(24) }
                        .frame(maxWidth: .infinity)
                    Divider()
                    DeviceSettings()
                        .frame(width: 480)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        devices.padding(24)
                        DeviceSettings()
                            .frame(minHeight: 640)
                            .scrollDisabled(true)
                    }
                }
            }
        }
        .navigationTitle("Devices")
        .measuringLayoutWidth()
        .onAppear { if !model.devices.hasLoaded { model.devices.refresh(engine: model.engine) } }
    }

    private var devices: some View {
        let center = model.devices
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("iPhone and iPad")
                        .font(.largeTitle.weight(.bold))
                    Text("Games built on this Mac install straight onto your devices, signed with your own Apple team. Saves, mods and cheats travel through the game's iCloud Drive folder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if center.isLoading { ProgressView().controlSize(.small) }
                Button("Refresh") { center.refresh(engine: model.engine) }
                    .disabled(center.isLoading || model.engine == nil)
            }
            if center.devices.isEmpty {
                ContentUnavailableView {
                    Label(center.hasLoaded ? "No Device Paired" : "Looking for Devices…", systemImage: "iphone.slash")
                } description: {
                    Text("Connect the iPhone or iPad with a cable, unlock it and choose Trust. Then turn on Developer Mode in Settings › Privacy & Security on the device.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(center.devices) { device in
                    DeviceCard(device: device, games: model.games.filter { $0.deviceInstall?.device == device.udid })
                }
            }
            let elsewhere = model.games.filter { game in game.deviceInstall != nil && !center.devices.contains { $0.udid == game.deviceInstall?.device } }
            if !elsewhere.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Installed on a device this Mac does not list now")
                        .font(.headline)
                    ForEach(elsewhere) { game in
                        InstalledGameRow(game: game)
                    }
                }
            }
        }
    }
}

private struct DeviceCard: View {
    let device: AppleDevice
    let games: [Game]
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.installDevice) private var installDevice = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: device.systemImage)
                    .font(.system(size: 34))
                    .foregroundStyle(device.isReachable ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.title3.weight(.semibold))
                    Text(device.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if installDevice == device.udid || (installDevice.isEmpty && model.devices.selectedDevice?.udid == device.udid) {
                    Label("Installs go here", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Install Here") { installDevice = device.udid }
                        .controlSize(.small)
                        .help("Make this the device that Install puts games on")
                }
            }
            if device.developerMode == false {
                Label("Turn on Developer Mode on the device: Settings › Privacy & Security › Developer Mode (it restarts).", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if games.isEmpty {
                Text("No game installed from this Mac yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(games) { game in InstalledGameRow(game: game) }
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct InstalledGameRow: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            GameIcon(game: game, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.name).lineLimit(1)
                if let date = game.deviceInstall?.date {
                    Text("Installed \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Open") { model.selectedGameID = game.id }
                .controlSize(.small)
            Button("Install Again") { model.build(game, target: .device) }
                .controlSize(.small)
                .disabled(!model.canStartJob)
        }
    }
}
