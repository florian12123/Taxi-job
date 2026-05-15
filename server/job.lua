local ESX = exports['es_extended']:getSharedObject()

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
