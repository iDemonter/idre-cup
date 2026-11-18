import CoreLocation
import SwiftUI

// Предложение 11 (Figma «11 · Курорты: выбор, единый вид, горки»): ResortSwitcher, ResortPickerSheet, ResortRow, HillInfoSheet.

/// Что выбрано в листе курортов: Idre (с зоной) или другой курорт из каталога.
enum ResortChoice {
    case idre(zone: String?)
    case other(ResortSummary)
}

/// Название курорта в шапке карты — кнопка «Idre Fjäll ⌄», открывает выбор курорта.
struct ResortSwitcher: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Text(title)
                    .font(Typo.largeTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 24, height: 24)
                    .background(Palette.raised, in: Circle())
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), выбрать курорт")
    }
}

/// Лист выбора курорта: поиск, рядом, где катались друзья, курорты по районам, горки Стокгольма отдельно.
struct ResortPickerSheet: View {
    let resorts: [ResortSummary]
    let here: CLLocationCoordinate2D?
    let choose: (ResortChoice) -> Void
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var season: SeasonReply?

    private var others: [ResortSummary] { resorts.filter { !$0.isIdre } }

    private func distanceKm(_ resort: ResortSummary) -> Double? {
        guard let here else { return nil }
        let a = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let b = CLLocation(latitude: resort.center[0], longitude: resort.center[1])
        return a.distance(from: b) / 1000
    }

    /// Курорт → кто из друзей там катался в этом сезоне.
    private var friends: [String: [Person]] {
        var result: [String: [Person]] = [:]
        for row in season?.rows ?? [] where row.id != session.me?.id {
            let person = session.people.first { $0.id == row.id } ?? Person(id: row.id, name: row.name, isAdmin: false, avatar: nil)
            for name in row.resorts {
                result[name, default: []].append(person)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Рядом") {
                        idreRow(title: "Idre Fjäll", zone: nil)
                        idreRow(title: "Idre Himmelfjäll", zone: "Himmelfjäll")
                        ForEach(others.filter { (distanceKm($0) ?? .infinity) < 60 }.sorted { (distanceKm($0) ?? 0) < (distanceKm($1) ?? 0) }) { resort in
                            row(resort)
                        }
                    }
                    let visited = others.filter { friends[$0.name] != nil }
                    if !visited.isEmpty {
                        Section("Катались друзья") {
                            ForEach(visited) { row($0) }
                        }
                    }
                    Section("Åre и Vemdalen") {
                        ForEach(others.filter { $0.region != "Stockholm" }.sorted { $0.trails > $1.trails }) { row($0) }
                    }
                    Section("Горки Стокгольма") {
                        ForEach(others.filter { $0.region == "Stockholm" }.sorted { $0.trails > $1.trails }) { row($0, hill: true) }
                    }
                } else {
                    let found = others.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.region.localizedCaseInsensitiveContains(query) }
                    if "idre fjäll himmelfjäll".localizedCaseInsensitiveContains(query) {
                        idreRow(title: "Idre Fjäll", zone: nil)
                    }
                    ForEach(found) { row($0, hill: $0.region == "Stockholm") }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.base)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Курорт или горка")
            .navigationTitle("Курорты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .task { season = await session.season() }
    }

    private func idreRow(title: String, zone: String?) -> some View {
        Button {
            choose(.idre(zone: zone))
            dismiss()
        } label: {
            ResortRow(symbol: "mountain.2.fill", title: title, detail: zone == nil ? "своя 3D-модель · 41 трасса" : "25 трасс · рядом с Idre Fjäll", tag: nil, friends: [])
        }
        .listRowBackground(Palette.surface)
    }

    private func row(_ resort: ResortSummary, hill: Bool = false) -> some View {
        Button {
            choose(.other(resort))
            dismiss()
        } label: {
            var parts = ["\(resort.trails) \(Format.plural(resort.trails, "трасса", "трассы", "трасс"))"]
            if ResortModel.bundled.contains(resort.id) { parts.insert("своя 3D-модель", at: 0) }
            if let km = distanceKm(resort) {
                parts.append(km < 10 ? String(format: "%.1f км", km) : "\(Int(km)) км")
            }
            return ResortRow(symbol: hill ? "figure.skiing.downhill" : "mountain.2.fill", title: resort.name, detail: parts.joined(separator: " · "), tag: hill ? "ГОРКА" : nil, friends: friends[resort.name] ?? [])
        }
        .listRowBackground(Palette.surface)
    }
}

/// Строка курорта или горки в листе выбора.
struct ResortRow: View {
    let symbol: String
    let title: String
    let detail: String
    let tag: String?
    let friends: [Person]

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.accentText)
                .frame(width: 36, height: 36)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.badge, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s) {
                    Text(title)
                        .font(Typo.headline)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if let tag {
                        Text(tag)
                            .font(Typo.overline)
                            .foregroundStyle(Palette.accentText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.accentSoft, in: Capsule())
                    }
                }
                Text(detail)
                    .font(Typo.caption1)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: -8) {
                ForEach(friends.prefix(3), id: \.id) { person in
                    AvatarView(person: person, size: 24)
                }
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Лист горки или курорта под картой: сегодня (часы, открыто) и список трасс вместо чипов зон.
struct HillInfoSheet: View {
    let resort: ResortDetail
    let conditions: ConditionsReply?

    private var today: String? {
        guard let status = conditions?.status else { return nil }
        var parts: [String] = []
        if let closes = status.closes { parts.append("сегодня до \(closes)") }
        if let pistes = status.pistes, pistes.total > 0 { parts.append("открыто \(pistes.open) из \(pistes.total) трасс") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let today {
                Label(today, systemImage: "clock")
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.textPrimary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(resort.trails.filter { $0.label != nil || $0.name != nil }) { trail in
                        HStack(spacing: Spacing.m) {
                            ShapedPisteBadge(text: trail.label ?? "", difficulty: trail.difficulty, color: trail.color, size: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(trail.name ?? "Трасса \(trail.label ?? "")")
                                    .font(Typo.subheadline)
                                    .foregroundStyle(Palette.textPrimary)
                                Text("\(Int(trail.length)) м")
                                    .font(Typo.caption1)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxHeight: 170)
        }
        .padding(Spacing.l)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
        .padding(.horizontal, Spacing.screen)
    }
}
