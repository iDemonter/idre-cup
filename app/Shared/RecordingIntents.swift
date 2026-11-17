import AppIntents

/// Команды записи из Live Activity: кнопки «Пауза», «Дальше» и «Стоп» на экране блокировки.
/// Кнопки Live Activity выполняются в приложении, а не в расширении: обработчик задаёт приложение при запуске.
enum RecordingCommands {
    nonisolated(unsafe) static var handler: ((String) -> Void)?

    static func run(_ command: String) async {
        await MainActor.run { handler?(command) }
    }
}

struct PauseRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Пауза записи"

    func perform() async throws -> some IntentResult {
        await RecordingCommands.run("pause")
        return .result()
    }
}

struct ResumeRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Продолжить запись"

    func perform() async throws -> some IntentResult {
        await RecordingCommands.run("start")
        return .result()
    }
}

struct StopRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Остановить запись"

    func perform() async throws -> some IntentResult {
        await RecordingCommands.run("stop")
        return .result()
    }
}

/// Кнопка «Запись трека» в Пункте управления и на экране блокировки (RecordControl).
/// Как и кнопки Live Activity, выполняется в приложении: оно включает GPS даже из кармана (нужно разрешение «Всегда»).
struct SetRecordingIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Запись трека"

    @Parameter(title: "Запись")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        await RecordingCommands.run(value ? "start" : "stop")
        return .result()
    }
}
