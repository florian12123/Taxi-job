local ESX = exports['es_extended']:getSharedObject()
local lastNpcSuccess = {}

CreateThread(function()
    if GetResourceState('esx_society') ~= 'started' then
        print('^3[TaxiJob]^7 esx_society nicht gefunden – Society-Registrierung übersprungen.')
        return
    end

    TriggerEvent('esx_society:registerSociety', Config.JobName, 'Taxi', Config.SocietyName, Config.SocietyName, Config.SocietyName, {
        type = 'public',
    })
end)

local function spawnJobVehicle(source, model, props, cb)
    local spawn = Config.Zones.VehicleSpawnPoint
    local spawnPoint = vector3(spawn.Pos.x, spawn.Pos.y, spawn.Pos.z)
    local modelHash = joaat(model)

    if ESX.OneSync and ESX.OneSync.SpawnVehicle then
        ESX.OneSync.SpawnVehicle(modelHash, spawnPoint, spawn.Heading, props, function(netId)
            if not netId then
                cb(false)
                return
            end

            local vehicle = NetworkGetEntityFromNetworkId(netId)
            local timeout = 0

            while props.plate and vehicle ~= 0 and GetVehicleNumberPlateText(vehicle) ~= props.plate and timeout < 100 do
                Wait(0)
                timeout = timeout + 1
            end

            TaskWarpPedIntoVehicle(GetPlayerPed(source), vehicle, -1)
            cb(true)
        end)
        return
    end

    TriggerClientEvent('taxijob:spawnVehicleClient', source, model, props)
    cb(true)
end

ESX.RegisterServerCallback('taxijob:spawnVehicle', function(source, cb, model, props)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer or xPlayer.job.name ~= Config.JobName then
        cb(false)
        return
    end

    props = props or {}

    spawnJobVehicle(source, model, props, function(success)
        cb(success == true)
    end)
end)

ESX.RegisterServerCallback('taxijob:getTripLog', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer or xPlayer.job.name ~= Config.JobName then
        cb({})
        return
    end

    if not Config.TripLog or Config.TripLog.enabled == false then
        cb({})
        return
    end

    cb(GetDriverTrips(xPlayer.identifier, Config.TripLog.menuLimit or 15))
end)

RegisterNetEvent('taxijob:npcSuccess', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or xPlayer.job.name ~= Config.JobName then
        return
    end

    local now = os.clock()
    if lastNpcSuccess[src] and now - lastNpcSuccess[src] < 5 then
        return
    end

    lastNpcSuccess[src] = now

    local total = math.random(Config.NpcMissions.earnings.min, Config.NpcMissions.earnings.max)
    local playerMoney = ESX.Math.Round(total * (Config.NpcMissions.playerPercent / 100), 0)
    local societyMoney = total - playerMoney

    if GetResourceState('esx_addonaccount') ~= 'started' then
        xPlayer.addMoney(total, 'Taxi NPC')
        Config.Functions.serverNotify(src, Config.Locales.npc_earned:format(total, 0), 'success')
        return
    end

    TriggerEvent('esx_addonaccount:getSharedAccount', Config.SocietyName, function(account)
        if account then
            account.addMoney(societyMoney)
            xPlayer.addMoney(playerMoney, 'Taxi NPC')
            Config.Functions.serverNotify(src, Config.Locales.npc_earned:format(playerMoney, societyMoney), 'success')
        else
            xPlayer.addMoney(total, 'Taxi NPC')
            Config.Functions.serverNotify(src, Config.Locales.npc_earned:format(total, 0), 'success')
        end
    end)
end)
