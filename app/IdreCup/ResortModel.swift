import MapKit

/// 3D-модель курорта для вида «Модель»: трассы, рельеф, окружение и камеры.
/// У Idre файлы pistes.json, terrain.json, terrain.jpg, scenery.json; у других курортов
/// те же файлы с суффиксом «-<id>» (собирает workflow «3D-модель курорта», настройки — tools/models.json).
/// id совпадает с id курорта в каталоге сезона: по нему лист выбора курорта открывает модель.
struct ResortModel {
    let id: String
    let name: String
    let data: PisteData
    let terrain: TerrainData?
    let scenery: SceneryData?
    /// Имя раскраски горы в бандле (без .jpg).
    let textureName: String
    /// Общий вид модели и «Весь район».
    let overview: ModelCamera
    let area: ModelCamera
    /// Камера Apple Maps для «Весь район»: центр в метрах от вершины и расстояние.
    let areaMapCenter: (east: Double, north: Double)
    let areaMapDistance: Double

    var isIdre: Bool { id == "idre" }

    /// Idre Fjäll с соседним Himmelfjäll и вершиной Städjan.
    static func idre(data: PisteData, terrain: TerrainData?) -> ResortModel {
        ResortModel(
            id: "idre",
            name: "Idre Fjäll",
            data: data,
            terrain: terrain,
            scenery: SceneryData.load(),
            textureName: "terrain",
            // С юго-запада, как на официальной карте курорта.
            overview: ModelCamera(id: 0, east: -900, north: -350, distance: 6_400, heading: 55, pitch: 54),
            // С востока на запад: район вытянут с запада на восток и так целиком входит в высокий экран.
            area: ModelCamera(id: 0, east: -2_000, north: 1_350, distance: 16_000, heading: 270, pitch: 50),
            areaMapCenter: (-2_000, 1_350),
            areaMapDistance: 21_000
        )
    }

    /// Модели других курортов, которые лежат в приложении.
    static let bundled = ["are"]

    static func load(_ id: String) -> ResortModel? {
        switch id {
        case "are":
            guard let terrain = TerrainData.load("terrain-are") else { return nil }
            let data = PisteData.load("pistes-are")
            guard !data.pistes.isEmpty else { return nil }
            return ResortModel(
                id: "are",
                name: "Åre",
                data: data,
                terrain: terrain,
                scenery: SceneryData.load("scenery-are"),
                textureName: "terrain-are",
                // С юга, из долины: внизу посёлок, вверху Åreskutan, справа Björnen.
                overview: ModelCamera(id: 0, east: 300, north: -2_600, distance: 9_000, heading: 0, pitch: 52),
                // Åre by и Björnen целиком, с юго-востока.
                area: ModelCamera(id: 0, east: 900, north: -2_400, distance: 14_500, heading: 340, pitch: 48),
                areaMapCenter: (900, -2_400),
                areaMapDistance: 17_000
            )
        default:
            return nil
        }
    }

    /// «Весь район» на Apple Maps.
    var areaMapCamera: MapCamera {
        MapCamera(
            centerCoordinate: LocalFrame(origin: data.summitCoordinate).coordinate(east: areaMapCenter.east, north: areaMapCenter.north),
            distance: areaMapDistance,
            heading: area.heading,
            pitch: 40
        )
    }
}
