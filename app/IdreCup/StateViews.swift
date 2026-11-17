import Network
import SwiftUI

// Предложение 7 (Figma «7 · Загрузка, пусто, нет связи»): SkeletonView 35:243, EmptyState 28:297, NoticeBanner.

/// Заготовки строк вместо крутилки: та же форма, что у настоящих карточек, мерцают, пока идёт загрузка.
struct SkeletonList: View {
    var rows = 4
    /// Сверху карточка покрупнее (как карточка события или итогов).
    var card = true

    var body: some View {
        VStack(spacing: Spacing.m) {
            if card {
                SkeletonCard()
            }
            ForEach(0..<rows, id: \.self) { _ in
                SkeletonRow()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Загрузка")
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: Spacing.m) {
            bar(width: 14, height: 18)
            Circle().fill(Palette.raised).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: Spacing.s) {
                bar(width: 120, height: 12)
                bar(width: 180, height: 10)
            }
            Spacer(minLength: 0)
            bar(width: 36, height: 22)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shimmer()
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Palette.raised)
            .frame(width: width, height: height)
    }
}

struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            RoundedRectangle(cornerRadius: 5).fill(Palette.raised).frame(width: 140, height: 10)
            RoundedRectangle(cornerRadius: Radius.badge).fill(Palette.raised).frame(height: 40)
            RoundedRectangle(cornerRadius: 9).fill(Palette.raised).frame(width: 160, height: 18)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shimmer()
    }
}

extension View {
    /// Мягкое мерцание заготовки.
    func shimmer() -> some View {
        phaseAnimator([0.55, 1.0]) { view, phase in
            view.opacity(phase)
        } animation: { _ in
            .easeInOut(duration: 0.9)
        }
    }
}

/// Пустой раздел: что здесь будет и что сделать, с кнопкой.
struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String
    var button: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.accentText)
                .frame(width: 56, height: 56)
                .background(Palette.raised, in: Circle())
            Text(title)
                .font(Typo.title3)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(text)
                .font(Typo.footnote)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let button, let action {
                Button(action: action) {
                    Text(button)
                        .font(Typo.headline)
                        .foregroundStyle(Palette.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
    }
}

/// Жёлтый баннер сверху: «Нет связи». Запись трека от сети не зависит, точки уйдут на сервер позже.
struct NoticeBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .bold))
            Text(text)
                .font(Typo.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Palette.onWarning)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s + 2)
        .background(Palette.warning, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .padding(.horizontal, Spacing.screen)
        .padding(.bottom, Spacing.xs)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Есть ли сеть (NWPathMonitor). Для снимков экрана можно включить «нет связи»: -offlineTest YES.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published private(set) var isOffline = UserDefaults.standard.bool(forKey: "offlineTest")
    private let monitor = NWPathMonitor()

    private init() {
        guard !UserDefaults.standard.bool(forKey: "offlineTest") else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                withAnimation(.snappy) { self?.isOffline = path.status != .satisfied }
            }
        }
        monitor.start(queue: DispatchQueue(label: "idrecup.network"))
    }
}
