import PhotosUI
import SwiftUI
#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// Профиль: аватар и имя, кубок с кодом приглашения, участники.
/// Админ здесь же переименовывает и удаляет участников и меняет настройки кубка.
struct ProfileScreen: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var renamed: Person?
    @State private var newName = ""
    @State private var removed: Person?
    @State private var asksSignOut = false
    @State private var asksNewCode = false
    @State private var firstDay = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Профиль")
                        .font(Theme.title(28))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.raised, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let me = session.me {
                    meCard(me)
                }
                if let problem = session.problem {
                    Text(problem)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.pisteRed)
                }
                if let cup = session.cup {
                    cupCard(cup)
                    peopleCard
                    if session.isAdmin {
                        adminCard(cup)
                    }
                }

                Button {
                    asksSignOut = true
                } label: {
                    Text("Выйти из кубка на этом телефоне")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.pisteRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(Theme.base.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            name = session.me?.name ?? ""
            if let start = session.cup?.startsOn, let date = Self.dayFormatter.date(from: start) {
                firstDay = date
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await session.setAvatar(image)
                }
                pickedPhoto = nil
            }
        }
        .alert("Новое имя", isPresented: Binding(get: { renamed != nil }, set: { if !$0 { renamed = nil } })) {
            TextField("Имя", text: $newName)
            Button("Сохранить") {
                if let person = renamed {
                    Task { await session.rename(person, to: newName) }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Удалить из кубка: \(removed?.name ?? "")?",
            isPresented: Binding(get: { removed != nil }, set: { if !$0 { removed = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let person = removed {
                    Task { await session.remove(person) }
                }
            }
        } message: {
            Text("Его очки пропадут из зачёта. Вернуться он сможет только заново, по коду.")
        }
        .confirmationDialog("Выдать новый код?", isPresented: $asksNewCode, titleVisibility: .visible) {
            Button("Выдать новый код") {
                Task { await session.newCode() }
            }
        } message: {
            Text("Старый код перестанет работать. Те, кто уже в кубке, останутся.")
        }
        .confirmationDialog("Выйти из кубка?", isPresented: $asksSignOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                session.signOut()
                dismiss()
            }
        } message: {
            Text("Телефон забудет кубок. Вернуться можно будет только новым участником, очки останутся у старого.")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Я

    private func meCard(_ me: Person) -> some View {
        VStack(spacing: 14) {
            AvatarView(person: me, size: 112)

            HStack(spacing: 8) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    chip("Фото", symbol: "photo")
                }
                .buttonStyle(.plain)
                PlaygroundButton { image in
                    Task { await session.setAvatar(image) }
                }
                if me.avatar != nil {
                    Button {
                        Task { await session.removeAvatar() }
                    } label: {
                        chip("Убрать", symbol: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("", text: $name, prompt: Text("Имя").foregroundStyle(Theme.textSecondary.opacity(0.7)))
                    .font(Theme.headline())
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if name.trimmingCharacters(in: .whitespaces) != me.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        Task { await session.rename(me, to: name.trimmingCharacters(in: .whitespaces)) }
                    } label: {
                        Text("Сохранить")
                            .font(Theme.caption())
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func chip(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
            Text(title)
        }
        .font(Theme.caption())
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.accent.opacity(0.18), in: Capsule())
    }

    // MARK: - Кубок

    private func cupCard(_ cup: CupInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("КУБОК")
                .font(Theme.overline())
                .foregroundStyle(Theme.textSecondary)
            Text(cup.name)
                .font(Theme.headline(19))
                .foregroundStyle(Theme.textPrimary)
            if let prize = cup.prize {
                Text("Приз: \(prize)")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("КОД ПРИГЛАШЕНИЯ")
                        .font(Theme.overline(10))
                        .foregroundStyle(Theme.textSecondary)
                    Text(cup.code)
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .textSelection(.enabled)
                }
                Spacer()
                ShareLink(item: "Заходи в «\(cup.name)» в приложении Idre Cup. Код: \(cup.code)") {
                    chip("Поделиться", symbol: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !cup.geofence {
                Text("Пробный кубок: спуски считаются где угодно.")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var peopleCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("УЧАСТНИКИ · \(session.people.count) ИЗ 8")
                .font(Theme.overline())
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 4)
            ForEach(session.people) { person in
                HStack(spacing: 12) {
                    AvatarView(person: person, size: 38)
                    Text(person.name)
                        .font(Theme.headline(16))
                        .foregroundStyle(Theme.textPrimary)
                    if person.isAdmin {
                        Text("админ")
                            .font(Theme.caption(10))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.18), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if session.isAdmin, person.id != session.me?.id {
                        Menu {
                            Button {
                                newName = person.name
                                renamed = person
                            } label: {
                                Label("Переименовать", systemImage: "pencil")
                            }
                            Button {
                                Task { await session.makeAdmin(person) }
                            } label: {
                                Label("Сделать админом", systemImage: "crown")
                            }
                            Button(role: .destructive) {
                                removed = person
                            } label: {
                                Label("Удалить из кубка", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(Theme.raised, in: Circle())
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Настройки админа

    private func adminCard(_ cup: CupInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("НАСТРОЙКИ КУБКА")
                .font(Theme.overline())
                .foregroundStyle(Theme.textSecondary)

            DatePicker("Первый день", selection: $firstDay, displayedComponents: .date)
                .font(Theme.headline(15))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .environment(\.locale, Format.russian)
            HStack(spacing: 8) {
                Button {
                    Task { await session.updateCup(["startsOn": Self.dayFormatter.string(from: firstDay)]) }
                } label: {
                    chip(cup.startsOn == nil ? "Задать даты" : "Сохранить дату", symbol: "calendar")
                }
                .buttonStyle(.plain)
                if cup.startsOn != nil {
                    Button {
                        Task { await session.updateCup(["startsOn": NSNull()]) }
                    } label: {
                        chip("Без дат", symbol: "calendar.badge.minus")
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(cup.startsOn == nil
                ? "Пока дат нет, в зачёт идут все дни с треками."
                : "Зачёт: \(cup.days) дней подряд, в последний очки удваиваются.")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)

            Toggle(isOn: Binding(
                get: { cup.geofence },
                set: { value in Task { await session.updateCup(["geofence": value]) } }
            )) {
                Text("Считать только в Idre Fjäll")
                    .font(Theme.headline(15))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)

            Button {
                asksNewCode = true
            } label: {
                chip("Новый код приглашения", symbol: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#if canImport(ImagePlayground)
/// Кнопка «Сгенерировать»: открывает Image Playground от Apple и возвращает готовую картинку.
/// Видна только там, где Apple Intelligence работает: подходящий iPhone и язык системы из списка Apple.
private struct PlaygroundButton: View {
    let onImage: (UIImage) -> Void

    @Environment(\.supportsImagePlayground) private var isSupported
    @State private var isShown = false

    var body: some View {
        if isSupported {
            Button {
                isShown = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text("Сгенерировать")
                }
                .font(Theme.caption())
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.accent.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .imagePlaygroundSheet(isPresented: $isShown, concept: "Portrait of a cheerful skier in ski goggles, snowy mountain") { url in
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    onImage(image)
                }
            }
        }
    }
}
#else
private struct PlaygroundButton: View {
    let onImage: (UIImage) -> Void

    var body: some View {
        EmptyView()
    }
}
#endif
