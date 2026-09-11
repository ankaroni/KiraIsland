import SwiftUI

struct AudioMixerSection: View {
    @ObservedObject var processes: AudioProcessMonitor
    @ObservedObject var mixer: PerAppAudioManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("App mixer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                if let error = mixer.errorMessage {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange.opacity(0.85))
                        .lineLimit(1)
                } else {
                    Text("\(processes.apps.count) active")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            if processes.apps.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.slash")
                    Text("No app is producing audio right now")
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(processes.apps) { app in
                            appRow(app)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }

    private func appRow(_ app: AudibleAudioApp) -> some View {
        let gain = mixer.gain(for: app)
        let percent = Int((gain * 100).rounded())

        return HStack(spacing: 8) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(app.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                    Circle()
                        .fill(.green)
                        .frame(width: 5, height: 5)
                }

                Slider(
                    value: Binding(
                        get: { Double(mixer.gain(for: app)) },
                        set: { mixer.setGain(Float($0), for: app) }
                    ),
                    in: 0...1
                )
                .controlSize(.mini)
            }

            Text("\(percent)%")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(.white.opacity(0.65))

            Button {
                mixer.toggleMute(for: app)
            } label: {
                Image(systemName: gain <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
