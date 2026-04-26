//
//  AnimeFilterEnums.swift
//  MyShikiPlayer
//

import Foundation

enum AnimeKind: String, CaseIterable, Sendable, Codable {
    case tv
    case tv13 = "tv_13"
    case tv24 = "tv_24"
    case tv48 = "tv_48"
    case movie
    case ova
    case ona
    case special
    case tvSpecial = "tv_special"
    case music
    case pv
    case cm

    var displayName: String {
        switch self {
        case .tv: return "TV Сериал"
        case .tv13: return "Короткие (до 13 эп.)"
        case .tv24: return "Средние (до 24 эп.)"
        case .tv48: return "Длинные (более 24 эп.)"
        case .movie: return "Фильм"
        case .ova: return "OVA"
        case .ona: return "ONA"
        case .special: return "Спецвыпуск"
        case .tvSpecial: return "TV Спецвыпуск"
        case .music: return "Клип"
        case .pv: return "Проморолик"
        case .cm: return "Реклама"
        }
    }
}

enum AnimeStatus: String, CaseIterable, Sendable, Codable {
    case anons
    case ongoing
    case released
    case latest

    var displayName: String {
        switch self {
        case .anons: return "Анонсировано"
        case .ongoing: return "Сейчас выходит"
        case .released: return "Вышедшее"
        case .latest: return "Недавно вышедшее"
        }
    }
}

enum AnimeRating: String, CaseIterable, Sendable, Codable {
    case g
    case pg
    case pg13 = "pg_13"
    case r
    case rPlus = "r_plus"
    case rx

    var displayName: String {
        switch self {
        case .g: return "G"
        case .pg: return "PG"
        case .pg13: return "PG-13"
        case .r: return "R-17"
        case .rPlus: return "R+"
        case .rx: return "Rx"
        }
    }
}

enum AnimeDuration: String, CaseIterable, Sendable, Codable {
    case short = "S"
    case medium = "D"
    case long = "F"

    var displayName: String {
        switch self {
        case .short: return "До 10 минут"
        case .medium: return "До 30 минут"
        case .long: return "Более 30 минут"
        }
    }
}

enum AnimeOrder: String, CaseIterable, Sendable, Codable {
    case ranked
    case kind
    case popularity
    case name
    case airedOn = "aired_on"
    case rankedRandom = "ranked_random"
    case rateScore = "rate_score"
    case rateId = "rate_id"
    case rateUpdated = "rate_updated"
    case episodes
    case status

    var displayName: String {
        switch self {
        case .ranked: return "По рейтингу"
        case .kind: return "По типу"
        case .popularity: return "По популярности"
        case .name: return "По алфавиту"
        case .airedOn: return "По дате выхода"
        case .rankedRandom: return "Случайно"
        case .rateScore: return "По оценке"
        case .rateId: return "По дате добавления"
        case .rateUpdated: return "По дате изменения"
        case .episodes: return "По числу эпизодов"
        case .status: return "По статусу"
        }
    }
}

enum AnimeOrigin: String, CaseIterable, Sendable, Codable {
    case original
    case manga
    case webManga = "web_manga"
    case fourKomaManga = "four_koma_manga"
    case novel
    case webNovel = "web_novel"
    case visualNovel = "visual_novel"
    case lightNovel = "light_novel"
    case game
    case cardGame = "card_game"
    case music
    case radio
    case book
    case pictureBook = "picture_book"
    case mixedMedia = "mixed_media"
    case other
    case unknown

    var displayName: String {
        switch self {
        case .original: return "Оригинал"
        case .manga: return "Манга"
        case .webManga: return "Веб-манга"
        case .fourKomaManga: return "Енкома"
        case .novel: return "Новелла"
        case .webNovel: return "Веб-новелла"
        case .visualNovel: return "Визуальная новелла"
        case .lightNovel: return "Ранобэ"
        case .game: return "Игра"
        case .cardGame: return "Карточная игра"
        case .music: return "Музыка"
        case .radio: return "Радио"
        case .book: return "Книга"
        case .pictureBook: return "Книга с картинками"
        case .mixedMedia: return "Более одного"
        case .other: return "Другое"
        case .unknown: return "Неизвестен"
        }
    }
}

/// Season preset as exposed by Shikimori sidebar (combines single-season, year, year-range and decade keys).
enum AnimeSeasonPreset: String, CaseIterable, Sendable, Codable {
    case summer2026 = "summer_2026"
    case spring2026 = "spring_2026"
    case winter2026 = "winter_2026"
    case fall2025 = "fall_2025"
    case year2026 = "2026"
    case year2025 = "2025"
    case range23to24 = "2023_2024"
    case range18to22 = "2018_2022"
    case range10to17 = "2010_2017"
    case range00to10 = "2000_2010"
    case decade1990s = "199x"
    case decade1980s = "198x"
    case ancient

    var displayName: String {
        switch self {
        case .summer2026: return "Лето 2026"
        case .spring2026: return "Весна 2026"
        case .winter2026: return "Зима 2026"
        case .fall2025: return "Осень 2025"
        case .year2026: return "2026 год"
        case .year2025: return "2025 год"
        case .range23to24: return "2023-2024"
        case .range18to22: return "2018-2022"
        case .range10to17: return "2010-2017"
        case .range00to10: return "2000-2010"
        case .decade1990s: return "1990-е годы"
        case .decade1980s: return "1980-е годы"
        case .ancient: return "Более старые"
        }
    }

    /// Returns the set of 4-digit years covered by this preset — used for client-side filtering
    /// against an `AnimeListViewModel.Item.year` string.
    var coveredYears: [String] {
        switch self {
        case .summer2026, .spring2026, .winter2026, .year2026: return ["2026"]
        case .fall2025, .year2025: return ["2025"]
        case .range23to24: return ["2023", "2024"]
        case .range18to22: return ["2018", "2019", "2020", "2021", "2022"]
        case .range10to17: return (2010...2017).map(String.init)
        case .range00to10: return (2000...2010).map(String.init)
        case .decade1990s: return (1990...1999).map(String.init)
        case .decade1980s: return (1980...1989).map(String.init)
        case .ancient: return (1900...1979).map(String.init)
        }
    }

    /// Single year used as a coarse key (the first one in the range). Nil for multi-year presets
    /// where a single representative year doesn't make sense.
    var yearPrefix: String? {
        coveredYears.first
    }
}

enum MyListStatus: String, CaseIterable, Sendable, Codable {
    case planned
    case watching
    case rewatching
    case completed
    case onHold = "on_hold"
    case dropped

    var displayName: String {
        switch self {
        case .planned: return "Запланировано"
        case .watching: return "Смотрю"
        case .rewatching: return "Пересматриваю"
        case .completed: return "Просмотрено"
        case .onHold: return "Отложено"
        case .dropped: return "Брошено"
        }
    }
}
