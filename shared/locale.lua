Locales = Locales or {}

---@param key string
---@return string
function L(key, ...)
    local locale = Config.Locale or 'de'
    local pack = Locales[locale] or Locales['de']

    if not pack then
        return key
    end

    local str = pack[key]
    if not str then
        str = Locales['de'] and Locales['de'][key] or key
    end

    if select('#', ...) > 0 then
        return string.format(str, ...)
    end

    return str
end
