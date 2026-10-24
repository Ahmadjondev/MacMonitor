import Foundation
import Combine

// Localization (en / ru / uz), switchable at runtime.
// Every view holds `@ObservedObject private var loc = Loc.shared`, so changing the
// language re-renders the whole UI live. Add a key to `table` and use `loc.t("key")`.

final class Loc: ObservableObject {
    static let shared = Loc()
    @Published var lang: String { didSet { UserDefaults.standard.set(lang, forKey: "lang") } }
    init() { lang = UserDefaults.standard.string(forKey: "lang") ?? "uz" }

    func t(_ key: String) -> String {
        let e = Loc.table[key] ?? [:]
        return e[lang] ?? e["en"] ?? key
    }

    static let langs = ["en", "ru", "uz"]
    static let langName: [String: String] = ["en": "EN", "ru": "RU", "uz": "UZ"]

    static let table: [String: [String: String]] = [
        "memory":          ["en": "Memory",       "ru": "Память",     "uz": "Xotira"],
        "processor":       ["en": "Processor",    "ru": "Процессор",  "uz": "Protsessor"],
        "network":         ["en": "Network",      "ru": "Сеть",       "uz": "Tarmoq"],
        "storage":         ["en": "Storage",      "ru": "Диск",       "uz": "Disk"],
        "top":             ["en": "Top memory",   "ru": "Топ память", "uz": "Eng ko'p"],
        "normal":          ["en": "Normal",       "ru": "Норма",      "uz": "Normal"],
        "warning":         ["en": "Warning",      "ru": "Внимание",   "uz": "Ogohlantirish"],
        "critical":        ["en": "Critical",     "ru": "Критично",   "uz": "Kritik"],
        "app":             ["en": "App",          "ru": "Прил.",      "uz": "App"],
        "wired":           ["en": "Wired",        "ru": "Wired",      "uz": "Wired"],
        "compressed":      ["en": "Compressed",   "ru": "Сжато",      "uz": "Siqilgan"],
        "cache":           ["en": "Cache",        "ru": "Кэш",        "uz": "Cache"],
        "swap":            ["en": "Swap",         "ru": "Swap",       "uz": "Swap"],
        "free":            ["en": "Free",         "ru": "Своб.",      "uz": "Bo'sh"],
        "clean_now":       ["en": "Clean now",    "ru": "Очистить",   "uz": "Hozir tozalash"],
        "cleaning":        ["en": "Cleaning…",    "ru": "Очистка…",   "uz": "Tozalanmoqda…"],
        "autoclean_short": ["en": "Auto-clean",   "ru": "Авто",       "uz": "Avto"],
        "quit":            ["en": "Quit",         "ru": "Выход",      "uz": "Chiqish"],
        "settings":        ["en": "Settings",     "ru": "Настройки",  "uz": "Sozlamalar"],
        "general":         ["en": "General",      "ru": "Общие",      "uz": "Umumiy"],
        "menu_bar":        ["en": "Menu bar",     "ru": "Строка меню", "uz": "Menyu paneli"],
        "bar_metric":      ["en": "Show",         "ru": "Показывать", "uz": "Ko'rsatish"],
        "update_interval": ["en": "Update rate",  "ru": "Интервал",   "uz": "Yangilanish"],
        "network_unit":    ["en": "Network unit", "ru": "Ед. сети",   "uz": "Tarmoq birligi"],
        "auto_clean":      ["en": "Auto-clean",   "ru": "Авто-очистка", "uz": "Avtomatik tozalash"],
        "auto_clean_desc": ["en": "Only when memory pressure is 🔴 critical",
                            "ru": "Только при 🔴 критическом давлении памяти",
                            "uz": "Faqat xotira bosimi 🔴 kritik bo'lganda"],
        "notify_desc":     ["en": "Alert when memory pressure turns 🔴 critical",
                            "ru": "Сообщать о 🔴 критическом давлении памяти",
                            "uz": "Xotira bosimi 🔴 kritik bo'lsa xabar beradi"],
        "purge_rule_missing": ["en": "Needs the sudoers rule from the README, otherwise skipped",
                            "ru": "Нужно правило sudoers из README, иначе пропускается",
                            "uz": "README'dagi sudoers qoidasi kerak, aks holda o'tkazib yuboriladi"],
        "launch_login_desc": ["en": "From your next login, menu bar only",
                            "ru": "Со следующего входа, только в строке меню",
                            "uz": "Keyingi login'dan, faqat menyu panelida"],
        "always_shown":    ["en": "Always shown", "ru": "Всегда видна", "uz": "Doim ko'rinadi"],
        "language":        ["en": "Language",     "ru": "Язык",       "uz": "Til"],
        "cards":           ["en": "Cards",        "ru": "Карточки",   "uz": "Kartalar"],
        "get_started":     ["en": "Get Started",  "ru": "Начать",     "uz": "Boshlash"],
        "pressure":        ["en": "Memory pressure", "ru": "Давление памяти", "uz": "Xotira bosimi"],
        "total":           ["en": "Total",        "ru": "Всего",      "uz": "Jami"],
        "cores":           ["en": "Cores",        "ru": "Ядра",       "uz": "Yadrolar"],
        "processes":       ["en": "Processes",    "ru": "Процессы",   "uz": "Jarayonlar"],
        "threads":         ["en": "Threads",      "ru": "Потоки",     "uz": "Oqimlar"],
        "packets":         ["en": "Packets",      "ru": "Пакеты",     "uz": "Paketlar"],
        "battery":         ["en": "Battery",      "ru": "Батарея",    "uz": "Batareya"],
        "gpu":             ["en": "GPU",          "ru": "GPU",        "uz": "GPU"],
        "health":          ["en": "Health",       "ru": "Состояние",  "uz": "Holati"],
        "cycles":          ["en": "Cycles",       "ru": "Циклы",      "uz": "Sikllar"],
        "session":         ["en": "Session",      "ru": "Сессия",     "uz": "Sessiya"],
        "welcome_sub":     ["en": "A beautiful system monitor for your Mac",
                            "ru": "Красивый системный монитор для вашего Mac",
                            "uz": "Mac uchun chiroyli tizim monitori"],
        "launch_login":    ["en": "Launch at login", "ru": "Запуск при входе", "uz": "Login'da ishga tushish"],
        "dashboard":       ["en": "Dashboard",    "ru": "Обзор",      "uz": "Asosiy"],
        "insights":        ["en": "Insights",     "ru": "Аналитика",  "uz": "Tahlil"],
        "now":             ["en": "Now",          "ru": "Сейчас",     "uz": "Hozir"],
        "average":         ["en": "Average",      "ru": "Среднее",    "uz": "O'rtacha"],
        "peak":            ["en": "Peak",         "ru": "Пик",        "uz": "Eng yuqori"],
        "pressure_events": ["en": "Critical (24h)", "ru": "Критич. (24ч)", "uz": "Kritik (24s)"],
        "open_activity":   ["en": "Activity Monitor", "ru": "Монитор системы", "uz": "Activity Monitor"],
        "notifications":   ["en": "Notifications", "ru": "Уведомления", "uz": "Bildirishnomalar"],
    ]
}
