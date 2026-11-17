import SwiftUI

/// Подиум топ-3 «Недели» (предложение 4, Figma PodiumView): 1-е место выше, с короной и аватаром 72.
struct PodiumView: View {
    let rows: [StandingRow]
    let person: (StandingRow) -> Person
    let myID: String?

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.s) {
            if rows.count > 1 { step(rows[1], height: 56, avatar: 44) }
            step(rows[0], height: 84, avatar: 72, crown: true)
            if rows.count > 2 { step(rows[2], height: 40, avatar: 44) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.l)
    }

    private func step(_ row: StandingRow, height: CGFloat, avatar: CGFloat, crown: Bool = false) -> some View {
        let isMe = row.id == myID
        return VStack(spacing: Spacing.xs) {
            if crown {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.accentText)
                    .symbolEffect(.bounce, value: row.id)
            }
            AvatarView(person: person(row), size: avatar)
            Text(row.name)
                .font(Typo.headline)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text(String(row.points))
                .font(crown ? Typo.numberL : Typo.numberM)
                .foregroundStyle(Palette.accentText)
                .contentTransition(.numericText(value: Double(row.points)))
            Text(String(row.place))
                .font(Typo.title2)
                .foregroundStyle(crown ? Palette.onAccent : Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(crown ? Palette.accent : Palette.surface, in: UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
                        .stroke(Palette.accent.opacity(isMe && !crown ? 0.7 : 0), lineWidth: 1.5)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

/// Стрелка «сколько мест отыграл за сегодня» (Figma RankDelta 35:192): ↑2 зелёным, ↓1 красным.
struct RankDelta: View {
    let change: Int

    var body: some View {
        if change != 0 {
            HStack(spacing: 1) {
                Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                Text(String(abs(change)))
            }
            .font(Typo.caption2)
            .foregroundStyle(change > 0 ? Palette.success : Palette.error)
            .accessibilityLabel(change > 0 ? "поднялся на \(change)" : "опустился на \(-change)")
        }
    }
}

extension StandingsReply {
    /// Насколько каждый поднялся за сегодня: место без сегодняшних очков минус место сейчас.
    /// Пусто, если сегодня ещё не зачётный день с треками.
    var placeChanges: [String: Int] {
        guard dates.last == today, dates.count > 1 else { return [:] }
        let before = rows.map { ($0.id, $0.points - ($0.days.last ?? 0)) }
        var changes: [String: Int] = [:]
        for row in rows {
            let mine = row.points - (row.days.last ?? 0)
            let placeBefore = 1 + before.filter { $0.1 > mine }.count
            changes[row.id] = placeBefore - row.place
        }
        return changes
    }
}
