import SwiftUI

struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var model: AppModel
    let onToggle: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: state.isExpanded ? 26 : 20, style: .continuous)
                .fill(.black)

            if state.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                compactContent
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggle)
                    .transition(.opacity)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: state.isExpanded ? 26 : 20, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var compactContent: some View {
        HStack(spacing: 9) {
            if model.timer.remainingSeconds > 0 {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(model.timer.formatted)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            } else {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                Text("\(model.audio.masterVolumePercent)%")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                VolumeWaveform(level: model.audio.masterVolume)
                    .frame(width: 54, height: 18)
            }

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                Image(systemName: model.battery.symbolName)
                Text("\(model.battery.percentage)%")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.68))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15)
    }

    private var expandedContent: some View {
        VStack(spacing: 12) {
            header
            tabBar

            Group {
                switch state.selectedTab {
                case .home: homeTab
                case .audio: audioTab
                case .clipboard: clipboardTab
                case .timer: timerTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white.opacity(0.09))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 17, weight: .semibold))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("Kira Island")
                    .font(.system(size: 15, weight: .semibold))
                Text("Native macOS control surface")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            HStack(spacing: 8) {
                VolumeWaveform(level: model.audio.masterVolume)
                    .frame(width: 48, height: 18)

                Text("\(model.audio.masterVolumePercent)%")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 7) {
                Image(systemName: model.battery.symbolName)
                Text("\(model.battery.percentage)%")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.68))

            Button(action: onToggle) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton(.home, icon: "sparkles", title: "Home")
            tabButton(.audio, icon: "speaker.wave.2.fill", title: "Audio")
            tabButton(.clipboard, icon: "doc.on.clipboard", title: "Clipboard")
            tabButton(.timer, icon: "timer", title: "Timer")
        }
        .padding(4)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func tabButton(_ tab: IslandState.Tab, icon: String, title: String) -> some View {
        Button {
            state.selectedTab = tab
            if tab == .audio { model.audio.refresh() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(state.selectedTab == tab ? .white : .white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                state.selectedTab == tab ? .white.opacity(0.11) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var homeTab: some View {
        HStack(spacing: 10) {
            statusCard(
                icon: model.battery.symbolName,
                title: "Battery",
                value: "\(model.battery.percentage)%",
                detail: model.battery.isCharging ? "Charging" : (model.battery.isPluggedIn ? "Power adapter" : "On battery")
            )

            statusCard(
                icon: volumeSymbol,
                title: "Volume",
                value: "\(model.audio.masterVolumePercent)%",
                detail: selectedOutputName
            )

            statusCard(
                icon: "doc.on.clipboard",
                title: "Clipboard",
                value: "\(model.clipboard.entries.count)",
                detail: "Recent text items"
            )
        }
    }

    private var audioTab: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Output device")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(model.audio.masterVolumePercent)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                Button("Refresh") { model.audio.refresh() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.audio.outputs) { device in
                        Button {
                            model.audio.select(device)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: device.symbolName)
                                Text(device.name)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(
                                model.audio.selectedID == device.id ? .white.opacity(0.16) : .white.opacity(0.07),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(
                        value: Binding(
                            get: { Double(model.audio.masterVolume) },
                            set: { model.audio.setVolume(Float($0)) }
                        ),
                        in: 0...1
                    )
                    Image(systemName: "speaker.wave.3.fill")
                }
                .font(.system(size: 11))

                if !model.audio.canControlVolume {
                    Text("This output does not expose hardware volume control.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    private var clipboardTab: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Recent clipboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if !model.clipboard.entries.isEmpty {
                    Button("Clear") { model.clipboard.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if model.clipboard.entries.isEmpty {
                emptyState(icon: "doc.on.clipboard", text: "Copy text and it will appear here")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.clipboard.entries.prefix(5)) { entry in
                            Button { model.clipboard.copy(entry) } label: {
                                HStack {
                                    Text(entry.text)
                                        .font(.system(size: 10.5))
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "doc.on.doc")
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var timerTab: some View {
        VStack(spacing: 13) {
            Text(model.timer.remainingSeconds > 0 ? model.timer.formatted : "00:00")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()

            if model.timer.remainingSeconds == 0 {
                HStack(spacing: 8) {
                    timerPreset(5)
                    timerPreset(10)
                    timerPreset(25)
                    timerPreset(45)
                }
            } else {
                HStack(spacing: 10) {
                    Button(model.timer.isRunning ? "Pause" : "Resume") { model.timer.togglePause() }
                        .buttonStyle(.bordered)
                    Button("Reset") { model.timer.reset() }
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func timerPreset(_ minutes: Int) -> some View {
        Button("\(minutes)m") { model.timer.start(minutes: minutes) }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusCard(icon: String, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
            Text(text)
                .font(.system(size: 10.5))
        }
        .foregroundStyle(.white.opacity(0.42))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedOutputName: String {
        model.audio.outputs.first(where: { $0.id == model.audio.selectedID })?.name ?? "Unknown"
    }

    private var volumeSymbol: String {
        switch model.audio.masterVolume {
        case ...0.001: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

private struct VolumeWaveform: View {
    let level: Float

    private let bars = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 5.2

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<bars, id: \.self) { index in
                    let normalizedLevel = max(0.08, Double(level))
                    let wave = abs(sin(phase + Double(index) * 0.72))
                    let height = 3.0 + (4.0 + wave * 10.0) * normalizedLevel

                    Capsule()
                        .fill(.white.opacity(level > 0.001 ? 0.82 : 0.24))
                        .frame(width: 2.6, height: height)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityLabel("System volume \(Int((level * 100).rounded())) percent")
    }
}
