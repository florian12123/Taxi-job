local ESX = exports['es_extended']:getSharedObject()

local hasSession = false
local meterCounting = false
local isDriver = false
local canUseMeter = false
local updateThread = false
local trackedVehicle = 0
local ratePrompted = false
local currentDriverId = nil
local passengerAgreed = false
local waitingAccept = false

local function notify(msg, nType)
    Config.Functions.notify(msg, nType)
end

local function isAllowedVehicle(vehicle)
    if not vehicle or vehicle == 0 then
        return false
    end

    local models = Config.VehicleModels or Config.AllowedVehicles
    if not models or #models == 0 then
        return true
    end

    local model = GetEntityModel(vehicle)
    for i = 1, #models do
        local name = type(models[i]) == 'table' and models[i].model or models[i]
        if model == joaat(name) then
            return true
        end
    end

    return false
end

local function hasTaxiJob()
    local data = ESX.GetPlayerData()
    return data.job and data.job.name == Config.JobName
end

local function refreshVehicleState()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    isDriver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
    canUseMeter = hasTaxiJob() and isDriver and isAllowedVehicle(vehicle)
    return vehicle
end

local function getWaypointCoords()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then
        return nil
    end

    local coords = GetBlipInfoIdCoord(blip)
    if not coords or (coords.x == 0.0 and coords.y == 0.0) then
        return nil
    end

    return { x = coords.x, y = coords.y, z = coords.z }
end

local function buildEstimateExtra(payload)
    if not Config.EstimatedFare or Config.EstimatedFare.enabled == false then
        return { hasEstimate = false }
    end

    if not payload then
        return { hasEstimate = false }
    end

    local waypoint = getWaypointCoords()
    local dest = waypoint

    if not dest and payload.destination and payload.destination.x then
        dest = payload.destination
    end

    if not dest or not dest.x then
        return { hasEstimate = false }
    end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local destVec = vector3(dest.x, dest.y, dest.z or pos.z)
    local distM = #(pos - destVec)
    local remainingKm = distM / 1000.0
    local drivenKm = payload.distanceKm or 0.0
    local totalKm = drivenKm + remainingKm
    local rate = payload.pricePerKm or Config.DefaultPricePerKm
    local baseFare = payload.baseFare or Config.BaseFare
    local estimatedFinal = 0.0

    if not Config.ChargeOnlyWhileDriving or totalKm > 0 then
        estimatedFinal = baseFare + (totalKm * rate)
    end

    estimatedFinal = ESX.Math.Round(math.max(estimatedFinal, 0), 2)

    if estimatedFinal <= 0 then
        return { hasEstimate = false }
    end

    return {
        hasEstimate = true,
        estimatedFinal = estimatedFinal,
    }
end

local function sendDisplay(payload, visible, extra)
    local merged = extra or {}
    local estimateExtra = buildEstimateExtra(payload)

    for key, value in pairs(estimateExtra) do
        merged[key] = value
    end

    SendNUIMessage({
        action = 'update',
        visible = visible,
        driver = isDriver,
        data = payload or {},
        extra = merged,
    })
end

local function hideMeter()
    hasSession = false
    meterCounting = false
    sendDisplay({}, false)
    SendNUIMessage({ action = 'hideAccept' })
    waitingAccept = false
end

local function getPassengerServerId()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        return nil
    end

    for seat = 0, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and ped ~= PlayerPedId() then
            local playerIndex = NetworkGetPlayerIndexFromPed(ped)
            if playerIndex ~= -1 then
                return GetPlayerServerId(playerIndex)
            end
        end
    end

    return nil
end

local function getDriverServerId()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        return nil
    end

    local driverPed = GetPedInVehicleSeat(vehicle, -1)
    if driverPed == 0 or driverPed == PlayerPedId() then
        return nil
    end

    local playerIndex = NetworkGetPlayerIndexFromPed(driverPed)
    if playerIndex == -1 then
        return nil
    end

    return GetPlayerServerId(playerIndex)
end

local rateUiOpen = false

local function closeRateUi()
    if not rateUiOpen then
        return
    end

    rateUiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideRate' })
end

local function openRateWindow(currentRate)
    if rateUiOpen then
        return
    end

    rateUiOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'showRate',
        title = Config.Locales.rate_dialog_title,
        subtitle = Config.Locales.rate_dialog_default:format(
            Config.DefaultPricePerKm,
            Config.MinPricePerKm,
            Config.MaxPricePerKm
        ),
        min = Config.MinPricePerKm,
        max = Config.MaxPricePerKm,
        defaultRate = currentRate or Config.DefaultPricePerKm,
        confirmLabel = hasSession and (Config.Locales.rate_confirm_change or 'Preis ändern') or Config.Locales.rate_confirm,
    })
end

RegisterNUICallback('confirmRate', function(data, cb)
    closeRateUi()

    local rate = tonumber(data and data.rate)
    if not rate or rate < Config.MinPricePerKm or rate > Config.MaxPricePerKm then
        notify(Config.Locales.rate_invalid:format(Config.MinPricePerKm, Config.MaxPricePerKm), 'error')
        cb('ok')
        return
    end

    TriggerServerEvent('av_taximeter:setRate', rate)
    cb('ok')
end)

RegisterNUICallback('cancelRate', function(_, cb)
    closeRateUi()
    cb('ok')
end)

local tipUiOpen = false
local pendingTipDriver = nil

local function closeTipUi()
    if not tipUiOpen then
        return
    end

    tipUiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideTip' })
end

RegisterNUICallback('tipPay', function(data, cb)
    local percent = tonumber(data and data.percent)
    if pendingTipDriver and percent then
        TriggerServerEvent('av_taximeter:giveTip', pendingTipDriver, percent)
    end
    pendingTipDriver = nil
    closeTipUi()
    cb('ok')
end)

RegisterNUICallback('tipSkip', function(_, cb)
    if pendingTipDriver then
        TriggerServerEvent('av_taximeter:skipTip', pendingTipDriver)
    end
    pendingTipDriver = nil
    closeTipUi()
    cb('ok')
end)

RegisterNetEvent('av_taximeter:showTip', function(data)
    if not data or not data.driverId then
        return
    end

    pendingTipDriver = data.driverId
    tipUiOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'showTip',
        title = Config.Locales.tip_title,
        info = Config.Locales.tip_info:format(data.fare, data.driverName or 'Fahrer'),
        skipLabel = Config.Locales.tip_skip,
        fare = data.fare,
        percents = data.percents or Config.Tips.percents,
        driverId = data.driverId,
    })
end)

local function startUpdateLoop()
    if updateThread then
        return
    end

    updateThread = true

    CreateThread(function()
        while meterCounting do
            local vehicle = refreshVehicleState()

            if not canUseMeter or vehicle == 0 or not hasSession then
                meterCounting = false
                break
            end

            local coords = GetEntityCoords(vehicle)
            local speed = GetEntitySpeed(vehicle) * 3.6
            local isDriving = speed >= Config.DrivingSpeedKmh

            TriggerServerEvent('av_taximeter:updatePosition', {
                x = coords.x,
                y = coords.y,
                z = coords.z,
            }, isDriving)

            Wait(Config.UpdateIntervalMs)
        end

        updateThread = false
    end)
end

local function stopUpdateLoop()
    meterCounting = false
end

local function showSession(payload)
    refreshVehicleState()

    hasSession = payload and payload.active ~= false

    if isDriver then
        sendDisplay(payload, hasSession, {
            pendingPassengers = payload and payload.pendingPassengers or 0,
            waitingForPassenger = payload and not payload.meterStarted,
        })
    end
end

local function promptDriverRate(vehicle)
    if ratePrompted and trackedVehicle == vehicle then
        return
    end

    ratePrompted = true
    trackedVehicle = vehicle
    openRateWindow()
end

local function showAcceptPrompt(payload, driverId)
    waitingAccept = true
    passengerAgreed = false
    currentDriverId = driverId

    SendNUIMessage({
        action = 'showAccept',
        acceptKey = Config.KeyMapping.accept or 'Y',
        title = Config.Locales.passenger_accept_title,
        info = Config.Locales.passenger_accept_info:format(
            payload.baseFare,
            payload.pricePerKm
        ),
        hint = Config.Locales.passenger_accept_hint:format(Config.KeyMapping.accept or 'Y'),
    })
end

local function acceptTariff()
    if not waitingAccept or not currentDriverId then
        return
    end

    TriggerServerEvent('av_taximeter:passengerAgree', currentDriverId)
end

RegisterNetEvent('av_taximeter:sessionState', function(payload)
    hasSession = payload and payload.active ~= false
    meterCounting = payload and payload.meterStarted or false

    showSession(payload)

    if meterCounting and isDriver then
        startUpdateLoop()
    else
        stopUpdateLoop()
    end
end)

RegisterNetEvent('av_taximeter:meterStarted', function(payload)
    hasSession = true
    meterCounting = true
    passengerAgreed = not isDriver

    if isDriver then
        showSession(payload)
        startUpdateLoop()
    else
        SendNUIMessage({ action = 'hideAccept' })
        sendDisplay(payload, true, {})
    end
end)

RegisterNetEvent('av_taximeter:updateDisplay', function(payload)
    refreshVehicleState()

    if isDriver then
        sendDisplay(payload, hasSession, {
            pendingPassengers = payload and payload.pendingPassengers or 0,
            waitingForPassenger = payload and not payload.meterStarted,
        })
    elseif passengerAgreed then
        sendDisplay(payload, true, {})
    end
end)

RegisterNetEvent('av_taximeter:syncDisplay', function(payload, driverId)
    refreshVehicleState()

    if isDriver then
        return
    end

    currentDriverId = driverId

    if payload.needsAccept and not passengerAgreed then
        showAcceptPrompt(payload, driverId)
        return
    end

    if passengerAgreed or payload.meterStarted then
        sendDisplay(payload, true, {})
    end
end)

RegisterNetEvent('av_taximeter:requestAccept', function(payload, driverId)
    refreshVehicleState()

    if isDriver then
        return
    end

    showAcceptPrompt(payload, driverId)
end)

RegisterNetEvent('av_taximeter:acceptConfirmed', function(payload)
    passengerAgreed = true
    waitingAccept = false
    meterCounting = payload and payload.meterStarted or false

    SendNUIMessage({ action = 'hideAccept' })

    if payload then
        sendDisplay(payload, true, {})
    end
end)

RegisterNetEvent('av_taximeter:hideAccept', function()
    waitingAccept = false
    passengerAgreed = false
    SendNUIMessage({ action = 'hideAccept' })

    if not isDriver then
        sendDisplay({}, false)
    end
end)

RegisterNetEvent('av_taximeter:promptRate', function()
    refreshVehicleState()
    if canUseMeter then
        openRateWindow()
    end
end)

local function resetTaximeterCompletely()
    closeRateUi()
    closeTipUi()
    hideMeter()
    stopUpdateLoop()
    ratePrompted = false
    trackedVehicle = 0
    currentDriverId = nil
    passengerAgreed = false
    waitingAccept = false
    TriggerServerEvent('av_taximeter:stop')
end

RegisterNetEvent('av_taxijob:resetTaximeter', resetTaximeterCompletely)

RegisterNetEvent('av_taximeter:forceHide', function()
    resetTaximeterCompletely()
end)

exports('ResetTaximeter', resetTaximeterCompletely)

RegisterCommand(Config.Command.setrate, function()
    refreshVehicleState()
    if not canUseMeter then
        notify(Config.Locales.not_in_vehicle, 'error')
        return
    end

    openRateWindow()
end, false)

RegisterCommand(Config.Command.reset, function()
    refreshVehicleState()
    if not canUseMeter or not hasSession then
        notify(Config.Locales.not_in_vehicle, 'error')
        return
    end

    if not meterCounting then
        notify(Config.Locales.passenger_must_accept, 'error')
        return
    end

    TriggerServerEvent('av_taximeter:reset')
end, false)

RegisterCommand(Config.Command.bill, function()
    refreshVehicleState()
    if not canUseMeter or not hasSession then
        notify(Config.Locales.not_in_vehicle, 'error')
        return
    end

    local passengerId = getPassengerServerId()
    if not passengerId then
        notify(Config.Locales.no_passenger, 'error')
        return
    end

    TriggerServerEvent('av_taximeter:billPassenger', passengerId)
end, false)

RegisterCommand(Config.Command.accept, function()
    acceptTariff()
end, false)

if Config.KeyMapping.setrate and Config.KeyMapping.setrate ~= '' then
    RegisterKeyMapping(Config.Command.setrate, 'Taxi Preis/km setzen', 'keyboard', Config.KeyMapping.setrate)
end

if Config.KeyMapping.reset and Config.KeyMapping.reset ~= '' then
    RegisterKeyMapping(Config.Command.reset, 'Taxameter Reset', 'keyboard', Config.KeyMapping.reset)
end

if Config.KeyMapping.bill and Config.KeyMapping.bill ~= '' then
    RegisterKeyMapping(Config.Command.bill, 'Taxifahrt abrechnen', 'keyboard', Config.KeyMapping.bill)
end

if Config.KeyMapping.accept and Config.KeyMapping.accept ~= '' then
    RegisterKeyMapping(Config.Command.accept, 'Taxitarif akzeptieren', 'keyboard', Config.KeyMapping.accept)
end

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    ESX.PlayerData = xPlayer
end)

RegisterNetEvent('esx:setJob', function(job)
    ESX.PlayerData.job = job
    if not hasTaxiJob() then
        hideMeter()
        stopUpdateLoop()
        ratePrompted = false
        TriggerServerEvent('av_taximeter:stop')
    end
end)

CreateThread(function()
    local wasPassenger = false
    local lastDriverId = nil

    while true do
        Wait(500)

        local vehicle = refreshVehicleState()
        local inVehicle = vehicle ~= 0

        if canUseMeter and Config.AutoStartMeter then
            if not hasSession and not rateUiOpen then
                promptDriverRate(vehicle)
            end
        elseif not canUseMeter and hasSession and isDriver then
            closeRateUi()
            hideMeter()
            stopUpdateLoop()
            ratePrompted = false
            trackedVehicle = 0
            TriggerServerEvent('av_taximeter:stop')
        end

        if inVehicle and not isDriver and not canUseMeter then
            local driverId = getDriverServerId()

            if driverId and driverId ~= lastDriverId then
                if lastDriverId then
                    TriggerServerEvent('av_taximeter:passengerLeft', lastDriverId)
                end

                lastDriverId = driverId
                currentDriverId = driverId
                passengerAgreed = false
                waitingAccept = false
                TriggerServerEvent('av_taximeter:passengerEntered', driverId)
            elseif not driverId and lastDriverId then
                TriggerServerEvent('av_taximeter:passengerLeft', lastDriverId)
                lastDriverId = nil
                currentDriverId = nil
                passengerAgreed = false
                waitingAccept = false
                SendNUIMessage({ action = 'hideAccept' })
            end
        elseif wasPassenger and lastDriverId then
            TriggerServerEvent('av_taximeter:passengerLeft', lastDriverId)
            lastDriverId = nil
            currentDriverId = nil
            passengerAgreed = false
            waitingAccept = false
            SendNUIMessage({ action = 'hideAccept' })
            hideMeter()
        end

        if not inVehicle then
            closeRateUi()
            ratePrompted = false
            trackedVehicle = 0

            if lastDriverId then
                TriggerServerEvent('av_taximeter:passengerLeft', lastDriverId)
                lastDriverId = nil
            end

            if not isDriver then
                passengerAgreed = false
                waitingAccept = false
                SendNUIMessage({ action = 'hideAccept' })
            end
        end

        wasPassenger = inVehicle and not isDriver and not canUseMeter
    end
end)

