local ESX = exports['es_extended']:getSharedObject()

local onNpcJob = false
local currentCustomer = nil
local currentCustomerBlip = nil
local destinationBlip = nil
local targetCoords = nil
local isNearCustomer = false
local customerEnteringVehicle = false
local customerEnteredVehicle = false
local lastSelectedNpc = nil

local function notify(msg, nType)
    Config.Functions.notify(msg, nType)
end

local function drawSub(msg, time)
    ClearPrints()
    BeginTextCommandPrint('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandPrint(time, 1)
end

local function canStartNpcJob()
    if not Config.NpcMissions.enabled then
        return false, Config.Locales.npc_too_many_players
    end

    if #GetActivePlayers() >= Config.NpcMissions.maxPlayersOnline then
        return false, Config.Locales.npc_too_many_players
    end

    return true
end

local function getRandomWalkingNpc()
    local search = {}
    local peds = GetGamePool('CPed')

    for i = 1, #peds do
        local ped = peds[i]
        if IsPedHuman(ped) and IsPedWalking(ped) and not IsPedAPlayer(ped) and ped ~= lastSelectedNpc then
            search[#search + 1] = ped
        end
    end

    if #search > 0 then
        local selected = search[math.random(#search)]
        lastSelectedNpc = selected
        return selected
    end

    return nil
end

function ClearNpcMission()
    if currentCustomerBlip and DoesBlipExist(currentCustomerBlip) then
        RemoveBlip(currentCustomerBlip)
    end

    if destinationBlip and DoesBlipExist(destinationBlip) then
        RemoveBlip(destinationBlip)
    end

    if currentCustomer and DoesEntityExist(currentCustomer) then
        SetEntityAsMissionEntity(currentCustomer, false, true)
    end

    currentCustomer = nil
    currentCustomerBlip = nil
    destinationBlip = nil
    isNearCustomer = false
    customerEnteringVehicle = false
    customerEnteredVehicle = false
    targetCoords = nil
end

local function stopNpcJob()
    if not onNpcJob then
        return
    end

    local playerPed = PlayerPedId()
    if IsPedInAnyVehicle(playerPed, false) and currentCustomer then
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        TaskLeaveVehicle(currentCustomer, vehicle, 0)
    end

    ClearNpcMission()
    onNpcJob = false
    notify(Config.Locales.npc_mission_complete, 'info')
end

local function startNpcJob()
    local ok, reason = canStartNpcJob()
    if not ok then
        notify(reason, 'error')
        return
    end

    local playerPed = PlayerPedId()
    if not IsPedInAnyVehicle(playerPed, false) or GetPedInVehicleSeat(GetVehiclePedIsIn(playerPed, false), -1) ~= playerPed then
        notify(Config.Locales.must_in_taxi, 'error')
        return
    end

    if not IsInAuthorizedVehicle() then
        notify(Config.Locales.only_taxi, 'error')
        return
    end

    ClearNpcMission()
    onNpcJob = true
    notify(Config.Locales.npc_drive_to_customer, 'info')
end

RegisterNetEvent('av_taxijob:startNpcJob', function()
    startNpcJob()
end)

RegisterNetEvent('av_taxijob:stopNpcJob', function()
    stopNpcJob()
end)

exports('IsNpcJobActive', function()
    return onNpcJob
end)

CreateThread(function()
    while true do
        local sleep = 1500

        if onNpcJob then
            sleep = 0
            local playerPed = PlayerPedId()

            if not IsPedInAnyVehicle(playerPed, false) then
                drawSub(Config.Locales.npc_return_to_veh, 1000)
            elseif currentCustomer == nil then
                drawSub(Config.Locales.npc_drive_to_customer, 2000)
                Wait(5000)

                if onNpcJob and IsPedInAnyVehicle(playerPed, false) then
                    currentCustomer = getRandomWalkingNpc()

                    if currentCustomer then
                        currentCustomerBlip = AddBlipForEntity(currentCustomer)
                        SetBlipAsFriendly(currentCustomerBlip, true)
                        SetBlipColour(currentCustomerBlip, 2)
                        SetBlipRoute(currentCustomerBlip, true)
                        SetEntityAsMissionEntity(currentCustomer, true, false)
                        ClearPedTasksImmediately(currentCustomer)
                        SetBlockingOfNonTemporaryEvents(currentCustomer, true)
                        TaskStandStill(currentCustomer, GetRandomIntInRange(60000, 180000))
                        notify(Config.Locales.npc_customer_found, 'success')
                    end
                end
            else
                if IsPedFatallyInjured(currentCustomer) then
                    notify(Config.Locales.npc_client_unconscious, 'error')
                    ClearNpcMission()
                else
                    local vehicle = GetVehiclePedIsIn(playerPed, false)
                    local playerCoords = GetEntityCoords(playerPed)
                    local customerCoords = GetEntityCoords(currentCustomer)
                    local customerDistance = #(playerCoords - customerCoords)

                    if IsPedSittingInVehicle(currentCustomer, vehicle) then
                        if customerEnteredVehicle and targetCoords then
                            local targetDistance = #(playerCoords - targetCoords)

                            if targetDistance <= 10.0 then
                                TaskLeaveVehicle(currentCustomer, vehicle, 0)
                                notify(Config.Locales.npc_arrive_dest, 'success')
                                TriggerServerEvent('av_taxijob:npcSuccess')

                                local customer = currentCustomer
                                SetTimeout(60000, function()
                                    if DoesEntityExist(customer) then
                                        DeleteEntity(customer)
                                    end
                                end)

                                ClearNpcMission()
                            end

                            DrawMarker(36, targetCoords.x, targetCoords.y, targetCoords.z + 1.1,
                                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                                1.0, 1.0, 1.0, 234, 223, 72, 155,
                                false, false, 2, true, nil, nil, false)
                        elseif not customerEnteredVehicle then
                            if currentCustomerBlip and DoesBlipExist(currentCustomerBlip) then
                                RemoveBlip(currentCustomerBlip)
                            end
                            currentCustomerBlip = nil

                            targetCoords = Config.JobLocations[math.random(#Config.JobLocations)]
                            local distance = #(playerCoords - targetCoords)
                            while distance < Config.NpcMissions.minDestinationDistance do
                                Wait(0)
                                targetCoords = Config.JobLocations[math.random(#Config.JobLocations)]
                                distance = #(playerCoords - targetCoords)
                            end

                            destinationBlip = AddBlipForCoord(targetCoords.x, targetCoords.y, targetCoords.z)
                            SetBlipRoute(destinationBlip, true)
                            BeginTextCommandSetBlipName('STRING')
                            AddTextComponentSubstringPlayerName('Ziel')
                            EndTextCommandSetBlipName(destinationBlip)

                            customerEnteredVehicle = true
                        end
                    else
                        DrawMarker(36, customerCoords.x, customerCoords.y, customerCoords.z + 1.1,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            1.0, 1.0, 1.0, 234, 223, 72, 155,
                            false, false, 2, true, nil, nil, false)

                        if customerDistance <= 40.0 and not isNearCustomer then
                            isNearCustomer = true
                            notify(Config.Locales.npc_close_to_client, 'info')
                        end

                        if customerDistance <= 20.0 and not customerEnteringVehicle then
                            ClearPedTasksImmediately(currentCustomer)
                            local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
                            local freeSeat = nil

                            for i = maxSeats - 1, 0, -1 do
                                if IsVehicleSeatFree(vehicle, i) then
                                    freeSeat = i
                                    break
                                end
                            end

                            if freeSeat then
                                TaskEnterVehicle(currentCustomer, vehicle, -1, freeSeat, 2.0, 0)
                                customerEnteringVehicle = true
                            end
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        Wait(10000)

        if onNpcJob and not IsInAuthorizedVehicle() then
            stopNpcJob()
            notify(Config.Locales.only_taxi, 'error')
        end
    end
end)
