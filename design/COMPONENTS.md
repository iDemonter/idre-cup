# Компоненты: Figma ↔ код

Файл Figma: [Idre Cup](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy). Страницы: «Основа» (токены), «Компоненты», «Экраны — сейчас», «Экраны — предложения», «Архив».

Правила:

- Имя компонента в Figma = имя SwiftUI-вьюхи. Если вьюхи пока нет, а есть функция внутри экрана (`rowCard()`, `tag()`), в столбце «Код» указана функция; при следующей правке этого места её выносят в отдельную вьюху с именем из Figma.
- Цвета, шрифты, отступы и радиусы в коде берутся только из `app/Shared/Design/Tokens.swift` (`Palette`, `Typo`, `Spacing`, `Radius`). Он генерируется из `design/tokens.json`: `node design/generate-tokens.js`.
- Новый компонент сначала рисуется на странице «Компоненты», потом появляется в коде и в этой таблице.
- Code Connect не подключён: на тарифе Figma Pro он недоступен (нужен Organization или Enterprise). Связь держится на этой таблице и на описаниях компонентов в Figma, где указан файл кода.

Статус: **есть** — отдельная вьюха уже есть; **вынести** — сейчас код внутри экрана; **новое** — пока только в Figma (из «Экраны — предложения»); **макет** — только для макетов, в код не идёт.

## Базовые

| Компонент Figma | Варианты | Код | Статус | Узел |
|---|---|---|---|---|
| StatusBar | — | системный | макет | [24:6](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=24-6) |
| HomeIndicator | — | системный | макет | [24:12](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=24-12) |
| AvatarView | Kind: Значок / Фото / Свой × Size: 24 / 32 / 44 / 72 / Маркер | `app/IdreCup/RatingScreen.swift` · `AvatarView`; значки — `PersonIcon.swift` | есть (размеры в коде 40–52 → свести к 24/32/44/72) | [24:45](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=24-45) |
| TagView | Стиль: Акцент / Мягкий / Ошибка / Нейтральный | `DuelsScreen.swift` · `tag()` | вынести | [24:55](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=24-55) |
| PisteBadge | Сложность × Размер 26 / 40 × Выбран | `MapScreen.swift` · `PisteBadge` (+ `TerrainView.swift`) | есть | [24:89](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=24-89) |
| LiftBadge | Тип: Гондола / Кресельный / Бугель / Якорный / Лента | `LiftIcon.swift` · `LiftIcon.badge`, `MapScreen.swift` · `LiftBadge` | есть | [24:120](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=24-120) |

## Управление

| Компонент Figma | Варианты | Код | Статус | Узел |
|---|---|---|---|---|
| IdreButton | Стиль: Основная / Вторичная / Удаление × Состояние: Обычная / Нажата / Неактивна × Размер: Большая / Обычная | `MyDayScreen.swift` · `bigButton()`, `DuelsScreen.swift` · `actionLabel()`, `EveningScreen.swift` · `actionButton()` | вынести (одна вьюха или `ButtonStyle`) | [25:60](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=25-60) |
| RecordButton | Состояние: Старт / Запись / Пауза / Демо | `MyDayScreen.swift` · `recordButton` | вынести | [25:84](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=25-84) |
| SegmentedPicker | Выбрано: 1 / 2 / 3 / 4; свойство «Сегмент 4 виден» | системный `Picker(.segmented)` (`RatingScreen.swift` · `Mode`: Сегодня / Неделя / Короны / Сезон, `NewDuelSheet`, `JoinView`) | есть | [25:107](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=25-107) |
| TabItem | Активна: Да / Нет | `RootView.swift` · `sectionBar` | вынести | [25:119](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=25-119) |
| SectionBar | Стиль: Сплошной (сейчас) / Стекло (предложение 1) | `RootView.swift` · `sectionBar` | вынести | [25:172](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=25-172) |
| ScreenHeader | Справа: Аватар / Кнопка / Закрыть / Нет | `header` в `RatingScreen`, `DuelsScreen`, `MapScreen`, `MyDayScreen`, `EveningScreen`, `ProfileScreen` | вынести | [25:197](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=25-197) |
| NoticeBanner | Тип: Подсказка / Предупреждение / Ошибка / Нет связи / Демо | `note()`, `warning()` в `RatingScreen`, `DuelsScreen`; `MyDayScreen` · `demoBanner`, `deniedNote`; «Нет связи» — `StateViews.swift` · `NoticeBanner` (в `RootView`) | вынести; «Нет связи» — есть | [25:214](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=25-214) |
| MapChip | Стиль: Обычный / Выбран / Жильё | `MapScreen.swift` · `presetChip()`, `homeChip` | вынести | [25:225](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=25-225) |
| IconButton | Вид: Закрыть / Ещё / Поделиться | `MapScreen.swift` · кнопка в `pisteCard()`, `ProfileScreen.swift` | вынести | [25:233](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=25-233) |
| FieldView | Состояние: Пусто / Заполнено / Фокус | `RatingScreen.swift` · `JoinView.field()` | вынести | [25:241](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=25-241) |

## Карточки

| Компонент Figma | Варианты | Код | Статус | Узел |
|---|---|---|---|---|
| LeaderboardRow | Вид: Обычная / Своя / Майка / Корона / Джокер / Со стрелкой (новое) | `RatingScreen.swift` · `rowCard()` | вынести | [28:112](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-112) |
| CrownRow | Вид: Обычная / Своя | `RatingScreen.swift` · `crownCard()` | вынести | [28:136](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-136) |
| EventCard | Состояние: Идёт / Итог | `EventsCard.swift` · `running()`, `finished()` | есть (`EventsCard`) | [28:170](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-170) |
| DuelCard | Состояние: Вызов / Идёт / Итог | `DuelsScreen.swift` · `incomingCard()`, `runningCard()`, `pastRow()` | вынести | [28:214](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-214) |
| StatTile | Вид: Награда / Показатель | `EveningScreen.swift` · `tile()`, `MyDayScreen.swift` · `volumeItem()` | вынести | [28:224](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-224) |
| SpeedCard | Данные: Есть / Нет | — (заменён DayHero, 17.11.2026) | убран | [28:240](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-240) |
| VolumeCard | — | — (заменён DayHero, 17.11.2026) | убран | [28:242](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-242) |
| SegmentRow | Тип: Спуск / Подъём | `MyDayScreen.swift` · `segmentRow()` | вынести | [28:274](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-274) |
| SegmentListCard | — | `MyDayScreen.swift` · `segmentList` | вынести | [37:409](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=37-409) |
| RecordingStatusPill | Состояние: Выключена / Идёт / Пауза | `MyDayScreen.swift` · `header` | вынести | [37:460](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=37-460) |
| RecordingCard | — | `MyDayScreen.swift` · `recordingCard` | вынести | [37:461](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=37-461) |
| PisteCard | Вид: Трасса / Место | `MapScreen.swift` · `pisteCard()`, `placeCard()` | вынести | [28:295](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-295) |
| EmptyState | — | `StateViews.swift` · `EmptyState` (пока в «Дуэлях») | есть | [28:297](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-297) |

## Вечер и игры

| Компонент Figma | Варианты | Код | Статус | Узел |
|---|---|---|---|---|
| CeremonyLine | — | `EveningScreen.swift` · `line()` | вынести | [30:88](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=30-88) |
| CeremonySection | — | `EveningScreen.swift` · `section()` | вынести | [30:94](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=30-94) |
| ReplayButton | — | `EveningScreen.swift` · `replayButton` | вынести | [30:121](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=30-121) |
| GameCard | Состояние: Старт / Итоги | `EveningScreen.swift` · `quizCard`, `gameCard`, `results()` | вынести | [30:157](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=30-157) |
| QuizOption | Буква: A–D × Выбран | `EveningScreen.swift` · `quizOption()` | вынести | [30:183](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=30-183) |
| QuizLive | — | `EveningScreen.swift` · `quizLive()` | вынести | [30:184](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=30-184) |
| ReactionView | Состояние: Готов / Жди / Жми / Результат / Фальстарт | `EveningScreen.swift` · `ReactionView` | есть | [30:242](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=30-242) |
| ReplayPanel | — | `ReplayView.swift` · `panel` | вынести | [30:244](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=30-244) |

## Профиль, дуэли, карта

| Компонент Figma | Варианты | Код | Статус | Узел |
|---|---|---|---|---|
| MeCard | — | `ProfileScreen.swift` · `meCard()` | вынести | [31:120](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-120) |
| CupCard | — | `ProfileScreen.swift` · `cupCard()` | вынести | [31:132](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-132) |
| PersonRow | Вид: Я / Участник | `ProfileScreen.swift` · `peopleCard` | вынести | [31:161](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-161) |
| PeopleCard | — | `ProfileScreen.swift` · `peopleCard` | вынести | [31:162](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-162) |
| ToggleRow | Включено: Да / Нет | системный `Toggle` в `adminCard()` | есть | [31:219](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-219) |
| AdminCard | — | `ProfileScreen.swift` · `adminCard()` | вынести | [31:220](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-220) |
| OpponentCell | Выбран: Нет / Да | `DuelsScreen.swift` · `NewDuelSheet.opponentButton()` | вынести | [31:245](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-245) |
| PickerRow | — | `DuelsScreen.swift` · `trailPicker` | вынести | [31:246](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-246) |
| MapLegend | — | `MapScreen.swift` · `bottomPanel` (легенда) | вынести | [31:250](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-250) |
| MapBottomPanel | Вид: Чипы / Карточка трассы | `MapScreen.swift` · `bottomPanel` | есть (функция) | [37:408](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=37-408) |
| MapControlButton | Стиль: Сплошной / Стекло × Вид: Где я / Вид | `MapScreen.swift` · `lookMenu`, кнопки карты Apple | вынести; стекло — новое | [31:296](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-296) |
| HomeBadge | — | `MapScreen.swift` · `HomeBadge` | есть | [31:297](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-297) |
| SummitMarker | — | `MapScreen.swift` · `SummitMarker`, `TerrainView.swift` | есть | [31:299](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=31-299) |
| SheetBackground | — | системный `.sheet` | макет | [37:464](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=37-464) |

## Условия, сезон, другие курорты

Из main 16.11.2026 (сборка b591991). Экраны: «Рейтинг · Сезон», «Рейтинг · Сегодня · в других местах», «Мой день · условия», «Мой день · подробности условий», «Карта · другие курорты» на странице «Экраны — сейчас»; полоса условий добавлена и в остальные экраны «Мой день».

| Компонент Figma | Варианты | Код | Статус | Узел |
|---|---|---|---|---|
| ConditionsStrip | — | `app/IdreCup/Conditions.swift` · `ConditionsStrip` | есть | [50:501](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=50-501) |
| ConditionsDetails | — (лист `.medium` / `.large`) | `Conditions.swift` · `ConditionsDetails` | есть | [50:643](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=50-643) |
| ConditionLine | — | `Conditions.swift` · `ConditionsDetails.line()` | вынести | [50:623](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=50-623) |
| LiftStatusRow | Статус: Открыт / Закрыт / Нет данных | `Conditions.swift` · список «ЛИФТЫ» в `ConditionsDetails` | вынести | [50:638](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=50-638) |
| HourForecast | — | `Conditions.swift` · ряд прогноза по часам | вынести | [50:639](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=50-639) |
| LeaderboardRow (в «Сезоне» и «В других местах») | Вид: Обычная / Своя; в «В других местах» — без места и очков | `RatingScreen.swift` · `seasonList`, `dayList` (`rowCard()`) | вынести | [28:112](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=28-112) |
| SeasonDayRow | — | `RatingScreen.swift` · `seasonList`, «МОИ ДНИ» | вынести | [50:720](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=50-720) |
| SeasonCrownRow | Своя: Да / Нет | `RatingScreen.swift` · `seasonList`, «КОРОНЫ СЕЗОНА» | вынести | [50:735](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=50-735) |
| OtherResortsChip | Состояние: Обычный / Выбран | `MapScreen.swift` · `otherResortsChip` | вынести | [50:743](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=50-743) |
| OtherResortsMenu | — (системное `Menu`, разделы по регионам) | `MapScreen.swift` · `otherResortsChip`, `OtherResorts.swift` | есть (системное меню) | [50:744](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=50-744) |

Расхождения макета с кодом (поправить при переходе на `Tokens.swift`): в сносках «Сезона» и «Мои дни» код пишет эмодзи 🤝 и 👑, в макете — текст «вместе 3», «корон 1» (значки только SF Symbols: `person.2.fill`, `crown.fill`); подписи `Theme.caption(10)` в полосе условий → `Typo.caption2` (11).

## Вне приложения

| Компонент Figma | Варианты | Код | Статус | Узел |
|---|---|---|---|---|
| RideLockScreenView | Состояние: Запись / Пауза / Нет данных | `app/Shared/RideLiveViews.swift` · `RideLockScreenView` | есть | [33:265](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=33-265) |
| DynamicIsland | Вид: Compact / Minimal / Expanded | `app/IdreCupLive/RideLive.swift` · `dynamicIsland` | есть | [33:279](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=33-279) |
| WatchHome | Состояние: Выключена / Запись / Пауза | `app/IdreCupWatch/WatchHome.swift` · `WatchHome` | есть | [33:324](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=33-324) |
| QuizTV | — (1920×1080) | `server/src/tv.js` | есть (веб-страница) | [33:326](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=33-326) |

## Новые (из «Экраны — предложения»)

| Компонент Figma | Варианты | Предложение | Статус | Узел |
|---|---|---|---|---|
| RankDelta | Изменение: Вверх / Вниз / Без изменений | 4 · подиум и стрелки | новое | [35:192](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=35-192) |
| PodiumView | — | 4 · подиум и стрелки | новое | [35:207](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=35-207) |
| SkeletonView | Вид: Строка / Карточка | 7 · загрузка · `StateViews.swift` · `SkeletonRow`, `SkeletonCard`, `SkeletonList` | есть | [35:243](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=35-243) |
| StoryCard | Слайд: Награда / Победитель | 6 · церемония | новое | [35:329](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=35-329) |
| MapSheet | Высота: Малая / Средняя / Большая | 2 · карта на весь экран | новое | [35:473](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=35-473) |
| RecordControl | Состояние: Выкл / Запись | 9 · Controls · `app/IdreCupLive/RideWidget.swift` · `RecordControl` | есть | [35:483](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=35-483) |
| RideWidget | Размер: Маленький / Средний / Экран блокировки | 9 · виджет · `app/IdreCupLive/RideWidget.swift` · `RideWidget` | есть | [35:510](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=35-510) |
| AppIcon | Вариант: Светлая / Тёмная / Tinted | 8 · иконка | новое (сейчас `Assets.xcassets/AppIcon` — одна тёмная) | [35:520](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=35-520) |
| DayHero | Состояние: Запись / Пауза | 3 · «Мой день» крупно · `app/IdreCup/DayHero.swift` (третье состояние «Запись выключена» — серая рамка, как Пауза) | есть | [42:451](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=42-451) |
| Note | Тип: Анимация / Хаптика / Доступность | пометки на макетах | макет | [35:531](https://www.figma.com/design/acerhjwP1YhbPlMWSAF0qy/Idre-Cup?node-id=35-531) |

## Токены

| Figma | Код | Где |
|---|---|---|
| Коллекция «Цвета» (Light, Dark), 41 переменная | `Palette.*`, `Palette.person[0…11]` | `design/tokens.json` → `app/Shared/Design/Tokens.swift` |
| Коллекция «Размеры»: Отступы | `Spacing.xs/s/m/l/xl/xxl/screen` = 4/8/12/16/24/32/20 | там же |
| Коллекция «Размеры»: Радиусы | `Radius.badge/control/card/cardLarge/capsule` = 10/14/18/24/999 | там же |
| Текстовые стили «Текст/…», «Цифры/…» | `Typo.*`, `.overlineStyle()` | там же |
| Стили эффектов «Стекло/Liquid Glass», «Стекло/iOS 18 · ultraThin» | `.glassBackground(in:)` | там же |

Сейчас код берёт цвета из `app/Shared/Theme.swift` (тёмная тема, те же значения, что Dark). Переход на `Tokens.swift` — отдельной задачей: `Theme.base` → `Palette.base`, `Theme.textSecondary` → `Palette.textSecondary`, `Theme.accent` текстом → `Palette.accentText`, `Theme.accent.opacity(0.18)` → `Palette.accentSoft`, `Theme.raised` → `Palette.raised`, `Theme.pisteRed.opacity(0.35)` → `Palette.errorSoft`, шрифты `Theme.title(32)` → `Typo.largeTitle` и т. д.
