local menuNamespace = 'av_taxijob'

---@param elements table
---@param onSelect function|nil
---@return boolean opened
function AVOpenMenu(elements, onSelect)
    if not elements or #elements == 0 then
        return false
    end

    if GetResourceState('esx_context') == 'started' then
        local opened = ESX.OpenContext('right', elements, function(_, element)
            if onSelect and element and not element.unselectable then
                onSelect(element)
            end
        end)

        if opened ~= false then
            return true
        end
    end

    local menuElements = {}

    for i = 1, #elements do
        local element = elements[i]
        if element.title then
            menuElements[#menuElements + 1] = {
                label = element.title,
                value = element.value,
                unselectable = element.unselectable,
            }
        end
    end

    if #menuElements == 0 then
        return false
    end

    local title = elements[1] and elements[1].title or 'Menu'

    ESX.UI.Menu.Open('default', GetCurrentResourceName(), menuNamespace, {
        title = title,
        align = 'top-right',
        elements = menuElements,
    }, function(data, menu)
        if data.current and data.current.unselectable then
            return
        end
        menu.close()
        if onSelect and data.current and data.current.value ~= nil then
            onSelect(data.current)
        end
    end, function(_, menu)
        menu.close()
    end)

    return true
end

function AVCloseMenu()
    if GetResourceState('esx_context') == 'started' then
        ESX.CloseContext()
    end

    ESX.UI.Menu.Close('default', GetCurrentResourceName(), menuNamespace)
end
