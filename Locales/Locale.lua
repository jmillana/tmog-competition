-- TmogCompetition: localization core. The strings live in Locales/<lang>.lua.
--
-- Usage:
--   local L = ns.L
--   L.MAIN_START                                      -- plain text
--   L:Format("CORE_ANNOUNCE_SCORE", { player = name, score = 8.5, count = 3 })
--
-- Placeholders are named, so a translation can put them in any order:
--   {player} -> tostring(value)      {score:.2f} -> ("%.2f"):format(value)
--
-- Lookup order: the selected language, then English, then the key itself (so a
-- missing key is visible in the UI instead of failing).
local ADDON, ns = ...

local L = {}
ns.L = L

ns.LANGUAGES = {
    { key = "auto", label = "SETTINGS_LANGUAGE_AUTO" }, -- translated
    { key = "enUS", label = "English" },                -- language names are shown in their own language
    { key = "esES", label = "Español" },
}

local locales = {}
local fallback, active

setmetatable(L, {
    __index = function(_, key)
        return (active and active[key]) or (fallback and fallback[key]) or key
    end,
})

-- Called by each Locales/<lang>.lua file.
function ns.RegisterLocale(lang, strings)
    locales[lang] = strings
    if lang == "enUS" then fallback = strings end
    if lang == ns.language then active = strings end
end

-- lang: "auto" (follow the game client), "enUS" or "esES".
function ns.SetLanguage(lang)
    if not lang or lang == "auto" then
        local locale = GetLocale()
        lang = (locale == "esES" or locale == "esMX") and "esES" or "enUS"
    end
    ns.language = lang
    active = locales[lang]
end

-- Fills named placeholders: {name} or {name:spec} where spec is a string.format spec (".2f", "d").
function L:Format(key, args)
    local text = self[key]
    return (text:gsub("{(%w+):?([^}]*)}", function(name, spec)
        local value = args and args[name]
        if value == nil then return "{" .. name .. "}" end
        if spec ~= "" then return ("%" .. spec):format(value) end
        return tostring(value)
    end))
end

local MONTHS = { "MONTH_JAN", "MONTH_FEB", "MONTH_MAR", "MONTH_APR", "MONTH_MAY", "MONTH_JUN",
    "MONTH_JUL", "MONTH_AUG", "MONTH_SEP", "MONTH_OCT", "MONTH_NOV", "MONTH_DEC" }
-- Localized "31 Oct 2026" style date.
function ns.FormatDate(timestamp)
    local t = date("*t", timestamp)
    return ("%d %s %d"):format(t.day, L[MONTHS[t.month]], t.year)
end

ns.SetLanguage("auto") -- refined from the saved setting once the database loads
