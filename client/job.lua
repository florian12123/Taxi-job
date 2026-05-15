local ESX = exports['es_extended']:getSharedObject()

local hasEnteredMarker = false
local lastZone = nil
local currentAction = nil
local currentActionMsg = nil
local currentActionData = {}

local function notify(msg, nType)
    Config.Functions.notify(msg, nType)
end

local function hasTaxiJob()
    local data = ESX.GetPlayerData()
    return data.job and data.job.name == Config.JobName
end

function IsInAuthorizedVehicle()
    local playerPed = PlayerPedId()
    if not IsPedInAnyVehicle(playerPed, false) then
        return false
    end

    local vehModel = GetEntityModel(GetVehiclePedIsIn(playerPed, false))

    for i = 1, #Config.AllowedVehicles do
        local entry = Config.AllowedVehicles[i]
        if entry.model and vehModel == joaat(entry.model) then
            return true
        end
    end

    return false
end

local function openCloakroom()
    local elements = {
        { unselectable = true, icon = 'fas fa-shirt', title = Config.Locales.menu_title },
        { icon = 'fas fa-shirt', title = Config.Locales.wear_civilian, value = 'civilian' },
        { icon = 'fas fa-shirt', title = Config.Locales.wear_work, value = 'work' },
    }

    AVOpenMenu(elements, function(element)
        if element.value == 'civilian' then
            if GetResourceState('esx_skin') ~= 'started' then
                notify('esx_skin wird benötigt.', 'error')
                return
            end
            ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin)
                TriggerEvent('skinchanger:loadSkin', skin)
            end)
        elseif element.value == 'work' then
            if GetResourceState('esx_skin') ~= 'started' then
                notify('esx_skin wird benötigt.', 'error')
                return
            end
            ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin, jobSkin)
                if skin.sex == 0 then
                    TriggerEvent('skinchanger:loadClothes', skin, jobSkin.skin_male)
                else
                    TriggerEvent('skinchanger:loadClothes', skin, jobSkin.skin_female)
                end
            end)
        end
    end)
end

local function openVehicleSpawner()
    local elements = {
        { unselectable = true, icon = 'fas fa-car', title = Config.Locales.menu_title },
    }

    for i = 1, #Config.AllowedVehicles do
        local v = Config.AllowedVehicles[i]
        elements[#elements + 1] = {
            icon = 'fas fa-car',
            title = v.title or v.model,
            value = v.model,
        }
    end

    AVOpenMenu(elements, function(element)
        if not element.value then
            return
        end

        local spawn = Config.Zones.VehicleSpawnPoint
        if not ESX.Game.IsSpawnPointClear(vector3(spawn.Pos.x, spawn.Pos.y, spawn.Pos.z), 5.0) then
            notify(Config.Locales.spawnpoint_blocked, 'error')
            return
        end

        ESX.TriggerServerCallback('av_taxijob:spawnVehicle', function()
            notify(Config.Locales.vehicle_spawned:format(element.title or element.value), 'success')
        end, element.value, { plate = 'TAXI' .. math.random(100, 999) })
    end)
end

local function deleteJobVehicle()
    local playerPed = PlayerPedId()
    local vehicle = currentActionData.vehicle

    if vehicle and DoesEntityExist(vehicle) then
        if IsInAuthorizedVehicle() then
            ESX.Game.DeleteVehicle(vehicle)
            TriggerEvent('av_taxijob:stopNpcJob')
            TriggerEvent('av_taxijob:resetTaximeter')
            notify(Config.Locales.vehicle_stored_meter_off, 'info')
        else
            notify(Config.Locales.only_taxi, 'error')
        end
    end
end

local function openTripLog()
    ESX.TriggerServerCallback('av_taxijob:getTripLog', function(trips)
        local elements = {
            { unselectable = true, icon = 'fas fa-book', title = Config.Locales.logbook_title },
        }

        if not trips or #trips == 0 then
            elements[#elements + 1] = { unselectable = true, title = Config.Locales.logbook_empty }
        else
            for i = 1, #trips do
                local trip = trips[i]
                local dateLabel = trip.created_at or '-'
                if type(dateLabel) == 'string' and #dateLabel > 16 then
                    dateLabel = dateLabel:sub(1, 16)
                end

                elements[#elements + 1] = {
                    unselectable = true,
                    icon = 'fas fa-route',
                    title = Config.Locales.logbook_entry:format(
                        dateLabel,
                        trip.distance_km or 0,
                        trip.total or trip.fare or 0,
                        trip.tip or 0
                    ),
                }
            end
        end

        AVOpenMenu(elements)
    end)
end

local function openMobileMenu()
    if not hasTaxiJob() then
        return
    end

    local elements = {
        { unselectable = true, icon = 'fas fa-taxi', title = Config.Locales.menu_title },
        { icon = 'fas fa-dollar-sign', title = Config.Locales.rate_confirm_change, value = 'setrate' },
    }

    if Config.TripLog and Config.TripLog.enabled ~= false then
        elements[#elements + 1] = { icon = 'fas fa-book', title = Config.Locales.logbook_menu, value = 'logbook' }
    end

    local playerCount = #GetActivePlayers()
    if Config.NpcMissions.enabled and playerCount < Config.NpcMissions.maxPlayersOnline then
        local npcActive = false
        pcall(function()
            npcActive = exports[GetCurrentResourceName()]:IsNpcJobActive()
        end)
        if npcActive then
            elements[#elements + 1] = { icon = 'fas fa-ban', title = Config.Locales.npc_stop, value = 'npc_stop' }
        else
            elements[#elements + 1] = { icon = 'fas fa-user', title = Config.Locales.npc_start, value = 'npc_start' }
        end
    end

    AVOpenMenu(elements, function(element)
        if element.value == 'setrate' then
            TriggerEvent('av_taxijob:openRateWindow')
        elseif element.value == 'logbook' then
            openTripLog()
        elseif element.value == 'npc_start' then
            TriggerEvent('av_taxijob:startNpcJob')
        elseif element.value == 'npc_stop' then
            TriggerEvent('av_taxijob:stopNpcJob')
        end
    end)
end

AddEventHandler('av_taxijob:hasEnteredMarker', function(zone)
    if zone == 'VehicleSpawner' then
        currentAction = 'vehicle_spawner'
        currentActionMsg = Config.Locales.spawner_prompt
        currentActionData = {}
    elseif zone == 'VehicleDeleter' then
        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false)

        if IsPedInAnyVehicle(playerPed, false) and GetPedInVehicleSeat(vehicle, -1) == playerPed then
            currentAction = 'delete_vehicle'
            currentActionMsg = Config.Locales.store_veh
            currentActionData = { vehicle = vehicle }
        end
    elseif zone == 'Cloakroom' then
        currentAction = 'cloakroom'
        currentActionMsg = Config.Locales.cloakroom_prompt
        currentActionData = {}
    end
end)

AddEventHandler('av_taxijob:hasExitedMarker', function()
    AVCloseMenu()
    currentAction = nil
end)

RegisterNetEvent('av_taxijob:spawnVehicleClient', function(model, props)
    local spawn = Config.Zones.VehicleSpawnPoint
    local spawnCoords = vector3(spawn.Pos.x, spawn.Pos.y, spawn.Pos.z)

    ESX.Game.SpawnVehicle(model, spawnCoords, spawn.Heading, function(vehicle)
        if props and props.plate then
            SetVehicleNumberPlateText(vehicle, props.plate)
        end
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    end)
end)

RegisterNetEvent('av_taxijob:openRateWindow', function()
    if hasTaxiJob() and IsPedInAnyVehicle(PlayerPedId(), false) and GetPedInVehicleSeat(GetVehiclePedIsIn(PlayerPedId(), false), -1) == PlayerPedId() then
        ExecuteCommand(Config.Command.setrate)
    else
        notify(Config.Locales.must_in_taxi, 'error')
    end
end)

CreateThread(function()
    local blip = AddBlipForCoord(Config.Zones.VehicleSpawner.Pos.x, Config.Zones.VehicleSpawner.Pos.y, Config.Zones.VehicleSpawner.Pos.z)
    SetBlipSprite(blip, 198)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.85)
    SetBlipColour(blip, 5)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.Locales.blip_taxi)
    EndTextCommandSetBlipName(blip)
end)

CreateThread(function()
    while true do
        local sleep = 1500

        if hasTaxiJob() then
            local coords = GetEntityCoords(PlayerPedId())
            local inMarker = false
            local currentZone = nil

            for name, zone in pairs(Config.Zones) do
                local zonePos = zone.Pos
                local distance = #(coords - zonePos)

                if zone.Type ~= -1 and distance < Config.DrawDistance then
                    sleep = 0
                    local col = zone.Color or { r = 204, g = 204, b = 0 }
                    DrawMarker(zone.Type, zonePos.x, zonePos.y, zonePos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        zone.Size.x, zone.Size.y, zone.Size.z,
                        col.r, col.g, col.b, 100,
                        false, false, 2, zone.Rotate, nil, nil, false)
                end

                if distance < zone.Size.x then
                    inMarker = true
                    currentZone = name
                end
            end

            if inMarker and (not hasEnteredMarker or lastZone ~= currentZone) then
                hasEnteredMarker = true
                lastZone = currentZone
                TriggerEvent('av_taxijob:hasEnteredMarker', currentZone)
            end

            if not inMarker and hasEnteredMarker then
                hasEnteredMarker = false
                TriggerEvent('av_taxijob:hasExitedMarker', lastZone)
                lastZone = nil
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1500

        local playerData = ESX.GetPlayerData()
        if currentAction and playerData and not playerData.dead and hasTaxiJob() then
            sleep = 0
            ESX.ShowHelpNotification(currentActionMsg)

            if IsControlJustReleased(0, 38) then
                if currentAction == 'cloakroom' then
                    openCloakroom()
                elseif currentAction == 'vehicle_spawner' then
                    openVehicleSpawner()
                elseif currentAction == 'delete_vehicle' then
                    deleteJobVehicle()
                end

                currentAction = nil
            end
        end

        Wait(sleep)
    end
end)

RegisterCommand('taxijobmenu', function()
    local playerData = ESX.GetPlayerData()
    if hasTaxiJob() and playerData and not playerData.dead then
        openMobileMenu()
    end
end, false)

RegisterKeyMapping('taxijobmenu', 'Taxi Job Menü', 'keyboard', Config.KeyMapping.menu or 'F6')
