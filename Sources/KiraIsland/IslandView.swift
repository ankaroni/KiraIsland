import SwiftUI

struct IslandView: View {
    let isExpanded: () -> Bool
    let onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black)

            if isExpanded() {
                expandedContent
            } else {
                compactContent
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onToggle() }
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)

            Text("Kira Island")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var expandedContent: some View {
        VStack(spacing: 16) {
            HStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.10))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.8))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing Playing")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Kira Island")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()
            }

            Divider().overlay(.white.opacity(0.10))

            HStack {
                item("speaker.wave.2.fill", "Audio")
                item("battery.75percent", "Battery")
                item("doc.on.clipboard", "Clipboard")
                item("timer", "Timer")
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func item(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 36, height: 36)
                .background(
                    .white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
    }
}
