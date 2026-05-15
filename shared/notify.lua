---@param msg string
---@param nType? string
function AVNotify(msg, nType)
    nType = nType or 'info'
    local mode = Config.Notify or 'auto'

    if mode == 'ox_lib' and GetResourceState('ox_lib') == 'started' then
        local ok = pcall(function()
            exports.ox_lib:notify({
                description = msg,
                type = nType == 'error' and 'error' or (nType == 'success' and 'success' or 'inform'),
            })
        end)
        if ok then
            return
        end
    end

    if ESX and ESX.ShowNotification then
        ESX.ShowNotification(msg, nType, 5000)
        return
    end

    TriggerEvent('esx:showNotification', msg)
end

---@param player number
---@param msg string
---@param nType? string
function AVNotifyServer(player, msg, nType)
    nType = nType or 'info'
    local mode = Config.Notify or 'auto'

    if mode == 'ox_lib' and GetResourceState('ox_lib') == 'started' then
        local ok = pcall(function()
            TriggerClientEvent('ox_lib:notify', player, {
                description = msg,
                type = nType == 'error' and 'error' or (nType == 'success' and 'success' or 'inform'),
            })
        end)
        if ok then
            return
        end
    end

    TriggerClientEvent('esx:showNotification', player, msg)
end
