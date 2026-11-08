import SwiftUI

/// L'icona dell'app, o un segnaposto se nell'IPA non ce n'era una leggibile.
struct AppIconView: View {
    let app: LibraryApp
    var side: CGFloat = 52

    var body: some View {
        Group {
            if app.hasIcon, let image = UIImage(contentsOfFile: app.iconFile.path) {
                Image(uiImage: image).resizable()
            } else {
                ZStack {
                    Rectangle().fill(.tertiary)
                    Image(systemName: "app.dashed")
                        .font(.system(size: side * 0.42))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
    }
}

/// Etichetta compatta per stato e avvisi.
struct StatusChip: View {
    enum Tone { case ok, warning, danger, neutral

        var color: Color {
            switch self {
            case .ok: return .green
            case .warning: return .orange
            case .danger: return .red
            case .neutral: return .secondary
            }
        }
    }

    let text: String
    var tone: Tone = .neutral
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tone.color.opacity(0.14), in: Capsule())
        .foregroundStyle(tone.color)
    }
}

/// Riga chiave/valore nelle schermate di dettaglio.
struct DetailRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .font(monospaced ? .callout.monospaced() : .callout)
        }
        .font(.callout)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

extension Date {
    var shortItalian: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: self)
    }
}
