import SwiftUI

struct AudioMixerSection: View {
    @ObservedObject var processes: AudioProcessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Now producing audio")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Text("\(processes.apps.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
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
                    VStack(spacing: 6) {
                        ForEach(processes.apps) { app in
                            HStack(spacing: 9) {
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

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text("Playing audio")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.green.opacity(0.8))
                                }

                                Spacer()

                                MiniAudioPulse(seed: app.id.hashValue)
                                    .frame(width: 36, height: 16)

                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(maxHeight: 105)
            }
        }
    }
}

private struct MiniAudioPulse: View {
    let seed: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 6.0 + Double(abs(seed % 17))
            HStack(alignment: .center, spacing: 1.8) {
                ForEach(0..<6, id: \.self) { index in
                    let height = 3 + abs(sin(phase + Double(index) * 0.8)) * 10
                    Capsule()
                        .fill(.white.opacity(0.7))
                        .frame(width: 2, height: height)
                }
            }
        }
    }
}
