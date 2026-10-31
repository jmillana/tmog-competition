-- TmogCompetition: localization (English and Spanish).
--
-- Usage: local L = ns.L; L["English text"]. The English text is the key, so a
-- missing translation falls back to English. Format strings keep the same
-- placeholders in the same order in every language.
local ADDON, ns = ...

local L = {}
ns.L = L

ns.LANGUAGES = {
    { key = "auto", label = "Automatic (game language)" },
    { key = "enUS", label = "English" },
    { key = "esES", label = "Español" },
}

local strings = {}
local active

setmetatable(L, {
    __index = function(_, key)
        return (active and active[key]) or key
    end,
})

-- lang: "auto" (follow the game client), "enUS" or "esES".
function ns.SetLanguage(lang)
    if not lang or lang == "auto" then
        local locale = GetLocale()
        lang = (locale == "esES" or locale == "esMX") and "esES" or "enUS"
    end
    active = strings[lang]
    ns.language = lang
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
-- Localized "31 Oct 2026" style date.
function ns.FormatDate(timestamp)
    local t = date("*t", timestamp)
    return ("%d %s %d"):format(t.day, L[MONTHS[t.month]], t.year)
end

------------------------------------------------------------------------
-- Spanish
------------------------------------------------------------------------
strings.esES = {
    -- Months (short)
    ["Jan"] = "ene", ["Feb"] = "feb", ["Mar"] = "mar", ["Apr"] = "abr", ["May"] = "may", ["Jun"] = "jun",
    ["Jul"] = "jul", ["Aug"] = "ago", ["Sep"] = "sep", ["Oct"] = "oct", ["Nov"] = "nov", ["Dec"] = "dic",

    -- Popups
    ["Yes"] = "Sí", ["No"] = "No", ["Accept"] = "Aceptar", ["Cancel"] = "Cancelar",

    -- Equipment slots
    ["Head"] = "Cabeza", ["Shoulder"] = "Hombros", ["Back"] = "Espalda", ["Chest"] = "Pecho",
    ["Shirt"] = "Camisa", ["Tabard"] = "Tabardo", ["Wrist"] = "Muñecas", ["Hands"] = "Manos",
    ["Waist"] = "Cintura", ["Legs"] = "Piernas", ["Feet"] = "Pies", ["Main Hand"] = "Mano principal",
    ["Off Hand"] = "Mano secundaria",

    -- Settings
    ["Settings"] = "Ajustes",
    ["Language"] = "Idioma",
    ["Automatic (game language)"] = "Automático (idioma del juego)",
    ["General"] = "General",
    ["Announce in group chat"] = "Anunciar en el chat del grupo",
    ["Post rounds, scores, themes and winners to party/raid chat (leader only)."] =
        "Publica rondas, puntuaciones, temáticas y ganadores en el chat de grupo/banda (solo el líder).",
    ["Open the window when a round starts"] = "Abrir la ventana al empezar una ronda",
    ["Show the competition window automatically when the leader starts a round."] =
        "Muestra la ventana de la competición automáticamente cuando el líder empieza una ronda.",
    ["Settings are saved for your account."] = "Los ajustes se guardan para tu cuenta.",

    -- Core messages
    ["Only the group leader can do that."] = "Solo el líder del grupo puede hacer eso.",
    ["Message too long, not sent: "] = "Mensaje demasiado largo, no enviado: ",
    ["You can't vote for yourself."] = "No puedes votarte a ti mismo.",
    ["You joined after this round started, so you can vote from the next round."] =
        "Te uniste después de que empezara esta ronda, podrás votar a partir de la siguiente.",
    ["Close the current voting before starting the next round."] =
        "Cierra la votación actual antes de empezar la siguiente ronda.",
    ["Everyone has already showcased. Reset the pool to start again."] =
        "Todos han desfilado ya. Reinicia el sorteo para volver a empezar.",
    ["Transmog round %d: %s is up! Cast your votes (%d-%d)."] =
        "Ronda de transfiguración %d: ¡le toca a %s! Votad (%d-%d).",
    ["No voting in progress."] = "No hay ninguna votación en curso.",
    ["%d vote(s) still pending. Close voting anyway?"] =
        "Aún faltan %d voto(s). ¿Cerrar la votación de todos modos?",
    ["%s scored %.2f (%d votes)."] = "%s ha obtenido %.2f (%d votos).",
    ["Close the current voting first."] = "Primero cierra la votación actual.",
    ["No results yet."] = "Todavía no hay resultados.",
    ["The transmog winner is %s with %.2f points!"] = "¡%s gana la competición de transfiguración con %.2f puntos!",
    ["It's a tie! %s with %.2f points!"] = "¡Empate! %s con %.2f puntos.",
    ["The winner of %s is %s with %.2f points!"] = "¡Ganador de la temática %s: %s con %.2f puntos!",
    ["It's a tie in %s! %s with %.2f points!"] = "¡Empate en la temática %s! %s con %.2f puntos.",
    ["This theme has results but no winner was announced. Spin anyway?\nIts results stay in its ranking tab."] =
        "Esta temática tiene resultados pero no se ha anunciado ganador. ¿Girar de todos modos?\nSus resultados se mantienen en su pestaña de clasificación.",

    -- Finishing the competition
    ["Finish Competition"] = "Terminar competición",
    ["Competition finished"] = "Competición terminada",
    ["End the competition and announce the overall ranking (sum of each player's theme scores)."] =
        "Termina la competición y anuncia la clasificación general (suma de las notas de cada temática).",
    ["The competition is already finished."] = "La competición ya ha terminado.",
    ["Finish the competition and announce the overall ranking?"] =
        "¿Terminar la competición y anunciar la clasificación general?",
    ["The competition is over! Overall winner: %s with %.2f points!"] =
        "¡La competición ha terminado! Ganador general: %s con %.2f puntos.",
    ["The competition is over! Overall tie: %s with %.2f points!"] =
        "¡La competición ha terminado! Empate general: %s con %.2f puntos.",
    ["%d. %s - %.2f (%d themes)"] = "%d. %s - %.2f (%d temáticas)",
    ["Overall"] = "General",
    ["PLAYER"] = "JUGADOR",
    ["POINTS"] = "PUNTOS",
    ["THEMES"] = "TEMÁTICAS",
    ["OVERALL WINNER"] = "GANADOR GENERAL",
    ["OVERALL WINNERS"] = "GANADORES GENERALES",
    ["Restart the round counter for each new competition"] = "Reiniciar el contador de rondas en cada competición",
    ["When a finished competition is followed by a new one, rounds count from 1 again (leader only). Reset All always restarts them."] =
        "Al empezar una competición nueva tras terminar la anterior, las rondas vuelven a contar desde 1 (solo el líder). Reiniciar todo siempre las reinicia.",
    ["%d. %s - %.2f (%d votes)"] = "%d. %s - %.2f (%d votos)",
    ["%d player(s) haven't showcased yet. Announce the winner anyway?"] =
        "%d jugador(es) aún no han desfilado. ¿Anunciar al ganador de todos modos?",
    ["Reset the shuffle pool? Everyone becomes eligible to showcase again (scores are kept)."] =
        "¿Reiniciar el sorteo? Todos podrán volver a desfilar (las puntuaciones se mantienen).",
    ["Reset the whole competition? All scores and the shuffle pool will be cleared."] =
        "¿Reiniciar toda la competición? Se borrarán todas las puntuaciones y el sorteo.",
    ["Chat announcements enabled."] = "Anuncios en el chat activados.",
    ["Chat announcements disabled."] = "Anuncios en el chat desactivados.",
    ["Open window on new round enabled."] = "Abrir la ventana en cada ronda: activado.",
    ["Open window on new round disabled."] = "Abrir la ventana en cada ronda: desactivado.",
    ["Commands:"] = "Comandos:",
    ["Couldn't read your outfit. Type /tmogc outfit to try again."] =
        "No se pudo leer tu atuendo. Escribe /tmogc outfit para intentarlo de nuevo.",

    -- Themes
    ["Type a theme name first."] = "Escribe primero el nombre de la temática.",
    ["Theme names can be up to %d characters."] = "Las temáticas pueden tener hasta %d caracteres.",
    ["\"%s\" is already on the list."] = "\"%s\" ya está en la lista.",
    ["Put every used theme back in the carousel?"] = "¿Devolver al carrusel todas las temáticas usadas?",
    ["The carousel is already spinning."] = "El carrusel ya está girando.",
    ["The theme pool is empty. Add themes or reset the used ones."] =
        "No quedan temáticas. Añade más o recupera las usadas.",
    ["The next transmog theme is: %s!"] = "¡La siguiente temática de transfiguración es: %s!",
    ["No theme"] = "Sin temática",

    -- Main window
    ["Transmog Competition"] = "Competición de transfiguración",
    ["WAITING"] = "EN ESPERA",
    ["VOTING OPEN"] = "VOTACIÓN ABIERTA",
    ["VOTING CLOSED"] = "VOTACIÓN CERRADA",
    ["Now showcasing"] = "En la pasarela",
    ["Your vote"] = "Tu voto",
    ["Leader controls"] = "Controles del líder",
    ["Shuffle & Start"] = "Sortear y empezar",
    ["Pick a random player who hasn't showcased yet and open voting."] =
        "Elige al azar a un jugador que aún no haya desfilado y abre la votación.",
    ["Close Voting"] = "Cerrar votación",
    ["End the current round and reveal the score."] = "Termina la ronda actual y muestra la puntuación.",
    ["Announce Winner"] = "Anunciar ganador",
    ["Announce the highest average score to the group."] = "Anuncia al grupo la media más alta.",
    ["Reset Pool"] = "Reiniciar sorteo",
    ["Make everyone eligible for the shuffle again. Scores are kept."] =
        "Todos vuelven a entrar en el sorteo. Las puntuaciones se mantienen.",
    ["Reset All"] = "Reiniciar todo",
    ["Clear all scores, outfits and the shuffle pool."] = "Borra puntuaciones, atuendos y el sorteo.",
    ["Refresh"] = "Actualizar",
    ["Ask everyone in the group to report that they have the addon, and resend the competition state."] =
        "Pide a todo el grupo que confirme que tiene el addon y reenvía el estado de la competición.",
    ["Only the group leader can run the competition."] = "Solo el líder del grupo puede dirigir la competición.",
    ["RANKING"] = "CLASIFICACIÓN",
    ["SCORE"] = "NOTA",
    ["VOTES"] = "VOTOS",
    ["Gallery"] = "Galería",
    ["Show every contestant's outfit with the current ranking."] =
        "Muestra el atuendo de cada participante con la clasificación.",
    ["Themes"] = "Temáticas",
    ["Open the theme carousel."] = "Abre el carrusel de temáticas.",
    ["Waiting for the next round."] = "Esperando a la siguiente ronda.",
    ["No one yet"] = "Nadie todavía",
    ["%d of %d voted"] = "%d de %d han votado",
    ["Waiting on "] = "Faltan ",
    ["All votes are in!"] = "¡Ya han votado todos!",
    ["from %d vote(s)"] = "de %d voto(s)",
    ["Press Shuffle & Start to pick the first contestant."] =
        "Pulsa Sortear y empezar para elegir al primer participante.",
    ["The leader will pick the next contestant."] = "El líder elegirá al siguiente participante.",
    ["Voting is closed"] = "La votación está cerrada",
    ["You're on stage! Strike a pose."] = "¡Estás en la pasarela! Posa.",
    ["You joined mid-round. Vote next round."] = "Te uniste a mitad de ronda. Vota en la siguiente.",
    ["Voted %s, click to change"] = "Has votado %s, pulsa para cambiar",
    ["Pick a score from %d to %d"] = "Elige una nota del %d al %d",
    ["on stage"] = "en pasarela",
    ["shown"] = "desfilado",
    ["waiting"] = "en espera",
    ["Round %d"] = "Ronda %d",
    ["Not started"] = "Sin empezar",
    ["Leader "] = "Líder ",
    ["Theme "] = "Temática ",
    ["WINNER"] = "GANADOR",
    ["WINNERS"] = "GANADORES",
    ["%s of %d still to showcase"] = "Faltan %s de %d por desfilar",
    ["Missing addon: "] = "Sin el addon: ",
    ["Move closer to %s to see their outfit."] = "Acércate a %s para ver su atuendo.",
    ["Shown on your character"] = "Mostrado en tu personaje",
    ["Outfit wasn't captured."] = "No se capturó el atuendo.",

    -- Gallery
    ["Transmog Gallery"] = "Galería de transfiguración",
    ["Rename competition"] = "Renombrar competición",
    ["Rename"] = "Renombrar",
    ["Explore"] = "Explorar",
    ["List every piece of this outfit with its item tooltip."] =
        "Muestra cada pieza de este atuendo con su descripción.",
    ["Clear all"] = "Borrar todo",
    ["Clear every saved transmog from your gallery?\nBookmarks are kept. This only affects you."] =
        "¿Borrar todas las transfiguraciones guardadas de tu galería?\nLos favoritos se mantienen. Solo te afecta a ti.",
    ["Delete your saved competitions. Bookmarks are kept."] =
        "Borra tus competiciones guardadas. Los favoritos se mantienen.",
    ["< Prev"] = "< Anterior",
    ["Next >"] = "Siguiente >",
    ["Bookmark"] = "Añadir a favoritos",
    ["Remove bookmark"] = "Quitar de favoritos",
    ["Remove from gallery"] = "Quitar de la galería",
    ["Bookmarks"] = "Favoritos",
    ["Your favourite looks from every competition. Right-click to remove one."] =
        "Tus atuendos favoritos de todas las competiciones. Clic derecho para quitar uno.",
    ["Right-click any transmog in a competition to bookmark it."] =
        "Haz clic derecho en cualquier transfiguración de una competición para añadirla a favoritos.",
    ["No rounds yet. Themes appear here as they're picked."] =
        "Aún no hay rondas. Las temáticas aparecerán aquí al elegirse.",
    ["Winner:"] = "Ganador:",
    ["Winners:"] = "Ganadores:",
    ["%s  -  %s  -  Drag to rotate, right-click for options"] =
        "%s  -  %s  -  Arrastra para girar, clic derecho para opciones",
    ["  %d votes"] = "  %d votos",
    ["Not scored yet"] = "Sin puntuar",
    ["Page %d of %d"] = "Página %d de %d",
    ["LIVE"] = "EN CURSO",

    -- Carousel
    ["Theme Carousel"] = "Carrusel de temáticas",
    ["No themes yet"] = "Aún no hay temáticas",
    ["Spin"] = "Girar",
    ["Spin for everyone. The theme it stops on is removed from the pool."] =
        "Gira para todos. La temática elegida se quita del carrusel.",
    ["Only the raid leader can add themes and spin."] = "Solo el líder de banda puede añadir temáticas y girar.",
    ["Reset used"] = "Recuperar usadas",
    ["Put every theme that was already picked back in the carousel."] =
        "Devuelve al carrusel todas las temáticas ya elegidas.",
    ["New theme, e.g. Pirates"] = "Nueva temática, p. ej. Piratas",
    ["Add"] = "Añadir",
    ["Remove this theme"] = "Quitar esta temática",
    ["SPINNING..."] = "GIRANDO...",
    ["THE NEXT THEME IS"] = "LA SIGUIENTE TEMÁTICA ES",
    ["CURRENT"] = "ACTUAL",
    ["USED"] = "USADA",
    ["CURRENT THEME"] = "TEMÁTICA ACTUAL",
    ["Add themes, then spin"] = "Añade temáticas y gira el carrusel",
    ["Waiting for the leader to spin"] = "Esperando a que el líder gire la ruleta",
    ["Themes  -  %d left, %d used"] = "Temáticas  -  quedan %d, %d usadas",

    -- Explore
    ["Explore Outfit"] = "Explorar atuendo",
    ["Hover a piece for its tooltip. Shift-click to link it in chat."] =
        "Pasa el ratón por una pieza para ver su descripción. Mayús+clic para enlazarla en el chat.",
    ["Try on"] = "Probar",
    ["Open the whole outfit in the dressing room."] = "Abre el atuendo completo en el probador.",
    ["Loading..."] = "Cargando...",
    ["Collected"] = "Conseguido",
    ["Not collected"] = "Sin conseguir",
    ["No pieces could be read for this outfit."] = "No se pudo leer ninguna pieza de este atuendo.",
    ["This outfit wasn't captured, so there is nothing to explore."] =
        "Este atuendo no se capturó, así que no hay nada que explorar.",
    ["Illusion: "] = "Ilusión: ",
}

ns.SetLanguage("auto") -- refined from the saved setting once the database loads
