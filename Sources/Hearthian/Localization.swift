import SwiftUI

enum Language: String, CaseIterable, Identifiable {
    case system, en, es
    var id: String { rawValue }

    var resolved: Language {
        guard self == .system else { return self }
        return Locale.preferredLanguages.first?.hasPrefix("es") == true ? .es : .en
    }
}

/// Every string the app shows. The day's own content comes from today.json as written.
enum L: String {
    case appTitle, focus, queue, parallel, whileWaiting, waiting, decisions, notToday
    case openDay, settings, quit, loading, noDay
    case messageAgent, newAgent, send, cancel, openLink, copyLine
    case agentFor, newAgentFor, typeMessage, jumpHelp, bbHelp, messageHelp, newAgentHelp
    case orcaFailed, noWorktree, language, systemLanguage, english, spanish
    case slackWindows, windowsEnabled, windowLength, minutesUnit, weekdayTimes, timesHelp, openSlackAtStart, quitSlackAtEnd, setSlackStatus, slackToken, slackTokenHelp, statusTexts, windowStarts, windowStartsBody, windowEnds, windowEndsBody, lastWindowBody, extendWindow, skipWindow, startWindowNow, endWindowNow, windowOpenUntil, nextWindow, general, monday, tuesday, wednesday, thursday, friday, saturday, sunday, saved
    case underway, roleFrog, roleWhileFrog, roleLight, descendTo, ascendTo, descendLocked, descendAnyway, whyDescend, waitingAbove, frogDone, promoteNext, activeNow, nextUp, everything, makeActive, kindDecision, kindAuto, kindLight, showAllPlanets, nothingHere, layerDone, backToFrog
    case noIssue, week, contractUnconfirmed, setSession, sessionFromClipboard, forgetSession, linkedSession, noSessionInClipboard
    case reload, updatedAt, agents, agentThinking, agentNeedsYou, agentStuck, agentIdle
    case updated, next, matrix, timeline, map, launchAtLogin, openAtLoginHelp

    private static let table: [L: (en: String, es: String)] = [
        .appTitle: ("Today", "Parte del día"),
        .focus: ("TIMBER HEARTH · MAIN QUEST", "TIMBER HEARTH · MISIÓN PRINCIPAL"),
        .queue: ("Brittle Hollow · Side quests", "Brittle Hollow · Misiones secundarias"),
        .parallel: ("The Brotherhood", "La Hermandad"),
        .whileWaiting: ("Giant's Deep · Collectibles", "Giant's Deep · Coleccionables"),
        .waiting: ("⏳ Waiting on someone", "⏳ Esperando a alguien"),
        .decisions: ("Decisions", "Decisiones"),
        .notToday: ("Not today", "Hoy no"),
        .openDay: ("Open day", "Abrir parte"),
        .settings: ("Settings…", "Ajustes…"),
        .quit: ("Quit", "Salir"),
        .loading: ("Loading…", "Cargando…"),
        .noDay: ("No plan for today yet. Waiting for today.json in", "Todavía no hay parte. Esperando today.json en"),
        .messageAgent: ("Message its agent", "Mensaje a su agente"),
        .newAgent: ("New agent", "Agente nuevo"),
        .send: ("Send", "Enviar"),
        .cancel: ("Cancel", "Cancelar"),
        .openLink: ("Open", "Abrir"),
        .copyLine: ("Copy line", "Copiar línea"),
        .agentFor: ("To the agent of", "Al agente de"),
        .newAgentFor: ("New agent for", "Agente nuevo para"),
        .typeMessage: ("Write the message… ⌘↩ to send", "Escribe el mensaje… ⌘↩ para enviar"),
        .jumpHelp: ("Go to its agent in Orca", "Ir a su agente en Orca"),
        .bbHelp: ("Go to its agent in bb", "Ir a su agente en bb"),
        .messageHelp: ("Message its live agent", "Mensaje a su agente activo"),
        .newAgentHelp: ("Start a new agent", "Arrancar un agente nuevo"),
        .orcaFailed: ("Orca did not answer", "Orca no ha respondido"),
        .noWorktree: ("No worktree for this item and no fallback worktree in", "No hay worktree para este item ni worktree de reserva en"),
        .language: ("Language", "Idioma"),
        .systemLanguage: ("System", "Sistema"),
        .english: ("English", "Inglés"),
        .spanish: ("Spanish", "Español"),
        .updated: ("Updated", "Actualizado"),
        .next: ("Next", "Ahora"),
        .map: ("Map", "Mapa"),
        .reload: ("Reload", "Recargar"),
        .underway: ("started", "empezada"),
        .roleFrog: ("Main quest: the minimum that makes the day", "Misión principal: lo mínimo para que el día sea bueno"),
        .roleWhileFrog: ("Side quests, for when the main quest waits", "Misiones secundarias, para cuando la principal espera"),
        .roleLight: ("Collectibles: small things with no agent", "Coleccionables: cosas pequeñas sin agente"),
        .descendTo: ("Go down to", "Bajar a"),
        .ascendTo: ("Back up to", "Subir a"),
        .descendLocked: ("Send a recruit on this one to go down", "Manda un recluta a por esta para bajar"),
        .descendAnyway: ("Go down anyway…", "Bajar igualmente…"),
        .whyDescend: ("Why go down without a recruit on it?", "¿Por qué bajas sin un recluta trabajando?"),
        .waitingAbove: ("They are waiting for you on", "Te esperan en"),
        .frogDone: ("Mission accomplished 🎉", "Misión cumplida 🎉"),
        .promoteNext: ("Make the next one the main quest", "Subir la siguiente a misión principal"),
        .activeNow: ("Active", "Activa"),
        .nextUp: ("Next", "Siguiente"),
        .everything: ("All", "Todas"),
        .makeActive: ("Work on this one", "Me pongo con esta"),
        .noIssue: ("no issue", "sin issue"),
        .week: ("Checkpoint", "Checkpoint"),
        .contractUnconfirmed: ("Not confirmed yet: confirm it before the morning reads it", "Sin confirmar: confírmalo antes de que lo lea el morning"),
        .setSession: ("Set session", "Asociar sesión"),
        .sessionFromClipboard: ("Session id from the clipboard", "Session id del portapapeles"),
        .forgetSession: ("Forget the session", "Olvidar la sesión"),
        .linkedSession: ("linked", "asociada"),
        .noSessionInClipboard: ("The clipboard holds no known session id", "El portapapeles no tiene ningún session id conocido"),
        .kindDecision: ("decision", "decisión"),
        .kindAuto: ("recruit", "recluta"),
        .kindLight: ("light", "ligera"),
        .showAllPlanets: ("Show every planet in the sidebar", "Ver todos los planetas en el sidebar"),
        .nothingHere: ("Nothing here today", "Hoy no hay nada aquí"),
        .layerDone: ("All done on this planet", "Todo hecho en este planeta"),
        .backToFrog: ("Back to the main quest", "Volver a la misión principal"),
        .agents: ("The Brotherhood", "La Hermandad"),
        .agentThinking: ("thinking", "pensando"),
        .agentNeedsYou: ("needs you", "te espera"),
        .agentStuck: ("stuck?", "¿colgado?"),
        .agentIdle: ("idle", "en reposo"),
        .updatedAt: ("Updated at", "Actualizado a las"),
        .slackWindows: ("Slack windows", "Ventanas de Slack"),
        .windowsEnabled: ("Open Slack only in windows", "Abrir Slack solo en ventanas"),
        .windowLength: ("Window length", "Duración de cada ventana"),
        .minutesUnit: ("min", "min"),
        .weekdayTimes: ("Times", "Horas"),
        .timesHelp: ("Comma separated, 24h: 09:20, 12:40, 16:30. The second field is when the day ends.", "Separadas por comas, 24 h: 09:20, 12:40, 16:30. El segundo campo es cuándo acaba el día."),
        .openSlackAtStart: ("Open Slack when a window starts", "Abrir Slack al empezar la ventana"),
        .quitSlackAtEnd: ("Quit Slack when it ends", "Cerrar Slack al acabar"),
        .setSlackStatus: ("Set my Slack status", "Poner mi estado de Slack"),
        .slackToken: ("Slack user token", "Token de usuario de Slack"),
        .slackTokenHelp: ("xoxp-…, with users.profile:write. Kept in the Keychain. Without it, windows still notify and open Slack.", "xoxp-…, con users.profile:write. Se guarda en el Llavero. Sin él, las ventanas siguen avisando y abriendo Slack."),
        .statusTexts: ("Status texts", "Textos del estado"),
        .windowStarts: ("Slack window", "Ventana de Slack"),
        .windowStartsBody: ("{minutes} minutes. Read, answer, close. What does not fit goes to Linear.", "{minutes} minutos. Lee, contesta, cierra. Lo que no cabe, a Linear."),
        .windowEnds: ("Window over", "Se acabó la ventana"),
        .windowEndsBody: ("Back to deep work. Next window at {next}.", "Vuelta al trabajo profundo. Siguiente a las {next}."),
        .lastWindowBody: ("That was the last one today.", "Era la última del día."),
        .extendWindow: ("+10 min", "+10 min"),
        .skipWindow: ("Close now", "Cerrar ya"),
        .startWindowNow: ("Open a window now", "Abrir una ventana ahora"),
        .endWindowNow: ("Close the window", "Cerrar la ventana"),
        .windowOpenUntil: ("Slack open until", "Slack abierto hasta las"),
        .nextWindow: ("Next Slack window", "Siguiente ventana de Slack"),
        .general: ("General", "General"),
        .monday: ("Monday", "Lunes"), .tuesday: ("Tuesday", "Martes"), .wednesday: ("Wednesday", "Miércoles"),
        .thursday: ("Thursday", "Jueves"), .friday: ("Friday", "Viernes"), .saturday: ("Saturday", "Sábado"),
        .sunday: ("Sunday", "Domingo"),
        .saved: ("Saved", "Guardado"),
        .matrix: ("Eisenhower matrix", "Matriz de Eisenhower"),
        .timeline: ("Timeline", "Timeline"),
        .launchAtLogin: ("Open at login", "Abrir al iniciar sesión"),
        .openAtLoginHelp: ("Keeps the menu bar item there from the moment you log in.", "Deja el ítem de la barra de menú puesto desde que inicias sesión."),
    ]

    @MainActor var text: String {
        let pair = Self.table[self] ?? (rawValue, rawValue)
        return AppSettings.shared.language.resolved == .es ? pair.es : pair.en
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @AppStorage("language") var languageRaw: String = Language.system.rawValue {
        willSet { objectWillChange.send() }
    }
    var language: Language { Language(rawValue: languageRaw) ?? .system }
}
