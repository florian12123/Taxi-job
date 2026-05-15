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
local rideBilled = false

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

    local dest = getWaypointCoords()

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

local function getUiLocaleExtra()
    return {
        pendingWaiting = L('meter_ui_wait_passenger'),
        pendingAccept = L('meter_ui_must_accept'),
        tripActive = L('meter_ui_trip_active'),
        driving = L('meter_ui_driving'),
        stopped = L('meter_ui_stopped'),
        statusOn = L('meter_ui_status_on'),
        statusReady = L('meter_ui_status_ready'),
        estimateLabel = L('meter_estimated_end'),
        labelTaxi = L('meter_ui_taxi'),
        labelDistance = L('meter_ui_distance'),
        labelStatus = L('meter_ui_status'),
        labelBase = L('meter_ui_base'),
        labelPerKm = L('meter_ui_per_km'),
        meterHint = L('meter_ui_commands'),
    }
end

local function sendDisplay(payload, visible, extra)
    local merged = extra or {}
    local estimateExtra = buildEstimateExtra(payload)
    local uiLocale = getUiLocaleExtra()

    for key, value in pairs(estimateExtra) do
        merged[key] = value
    end

    for key, value in pairs(uiLocale) do
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
        title = L('rate_dialog_title'),
        subtitle = L('rate_dialog_default', 
            Config.DefaultPricePerKm,
            Config.MinPricePerKm,
            Config.MaxPricePerKm
        ),
        min = Config.MinPricePerKm,
        max = Config.MaxPricePerKm,
        defaultRate = currentRate or Config.DefaultPricePerKm,
        confirmLabel = hasSession and L('rate_confirm_change') or L('rate_confirm'),
        cancelLabel = L('rate_cancel'),
        rateErrorTemplate = L('rate_error_invalid'),
    })
end

RegisterNUICallback('confirmRate', function(data, cb)
    closeRateUi()

    local rate = tonumber(data and data.rate)
    if not rate or rate < Config.MinPricePerKm or rate > Config.MaxPricePerKm then
        notify(L('rate_invalid', Config.MinPricePerKm, Config.MaxPricePerKm), 'error')
        cb('ok')
        return
    end

    TriggerServerEvent('taximeter:setRate', rate)
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
        TriggerServerEvent('taximeter:giveTip', pendingTipDriver, percent)
    end
    pendingTipDriver = nil
    closeTipUi()
    cb('ok')
end)

RegisterNUICallback('tipSkip', function(_, cb)
    if pendingTipDriver then
        TriggerServerEvent('taximeter:skipTip', pendingTipDriver)
    end
    pendingTipDriver = nil
    closeTipUi()
    cb('ok')
end)

RegisterNetEvent('taximeter:showTip', function(data)
    if not data or not data.driverId then
        return
    end

    pendingTipDriver = data.driverId
    tipUiOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'showTip',
        title = L('tip_title'),
        info = L('tip_info', data.fare, data.driverName or L('driver_default')),
        skipLabel = L('tip_skip'),
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

            TriggerServerEvent('taximeter:updatePosition', {
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
        title = L('passenger_accept_title'),
        info = L('passenger_accept_info', 
            payload.baseFare,
            payload.pricePerKm
        ),
        hint = L('passenger_accept_hint', Config.KeyMapping.accept or 'Y'),
    })
end

local function acceptTariff()
    if rideBilled or not waitingAccept or not currentDriverId then
        return
    end

    TriggerServerEvent('taximeter:passengerAgree', currentDriverId)
end

RegisterNetEvent('taximeter:sessionState', function(payload)
    hasSession = payload and payload.active ~= false
    meterCounting = payload and payload.meterStarted or false

    showSession(payload)

    if meterCounting and isDriver then
        startUpdateLoop()
    else
        stopUpdateLoop()
    end
end)

RegisterNetEvent('taximeter:meterStarted', function(payload)
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

RegisterNetEvent('taximeter:updateDisplay', function(payload)
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

RegisterNetEvent('taximeter:syncDisplay', function(payload, driverId)
    refreshVehicleState()

    if isDriver then
        return
    end

    currentDriverId = driverId

    if payload.rideBilled then
        rideBilled = true
        waitingAccept = false
        SendNUIMessage({ action = 'hideAccept' })
        sendDisplay({}, false)
        return
    end

    if payload.needsAccept and not passengerAgreed and not rideBilled then
        showAcceptPrompt(payload, driverId)
        return
    end

    if passengerAgreed or payload.meterStarted then
        sendDisplay(payload, true, {})
    end
end)

RegisterNetEvent('taximeter:requestAccept', function(payload, driverId)
    refreshVehicleState()

    if isDriver then
        return
    end

    rideBilled = false
    showAcceptPrompt(payload, driverId)
end)

RegisterNetEvent('taximeter:rideBilled', function()
    rideBilled = true
    waitingAccept = false
    passengerAgreed = false
    SendNUIMessage({ action = 'hideAccept' })
    sendDisplay({}, false)
    notify(L('ride_billed_passenger'), 'info')
end)

RegisterNetEvent('taximeter:acceptConfirmed', function(payload)
    rideBilled = false
    passengerAgreed = true
    waitingAccept = false
    meterCounting = payload and payload.meterStarted or false

    SendNUIMessage({ action = 'hideAccept' })

    if payload then
        sendDisplay(payload, true, {})
    end
end)

RegisterNetEvent('taximeter:hideAccept', function()
    waitingAccept = false
    passengerAgreed = false
    SendNUIMessage({ action = 'hideAccept' })

    if not isDriver then
        sendDisplay({}, false)
    end
end)

RegisterNetEvent('taximeter:promptRate', function()
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
    rideBilled = false
    TriggerServerEvent('taximeter:stop')
end

RegisterNetEvent('taxijob:resetTaximeter', resetTaximeterCompletely)

RegisterNetEvent('taximeter:forceHide', function()
    resetTaximeterCompletely()
end)

exports('ResetTaximeter', resetTaximeterCompletely)

RegisterCommand(Config.Command.setrate, function()
    refreshVehicleState()
    if not canUseMeter then
        notify(L('not_in_vehicle'), 'error')
        return
    end

    openRateWindow()
end, false)

RegisterCommand(Config.Command.reset, function()
    refreshVehicleState()
    if not canUseMeter or not hasSession then
        notify(L('not_in_vehicle'), 'error')
        return
    end

    TriggerServerEvent('taximeter:reset')
end, false)

RegisterCommand(Config.Command.bill, function()
    refreshVehicleState()
    if not canUseMeter or not hasSession then
        notify(L('not_in_vehicle'), 'error')
        return
    end

    local passengerId = getPassengerServerId()
    if not passengerId then
        notify(L('no_passenger'), 'error')
        return
    end

    TriggerServerEvent('taximeter:billPassenger', passengerId)
end, false)

RegisterCommand(Config.Command.accept, function()
    acceptTariff()
end, false)

if Config.KeyMapping.setrate and Config.KeyMapping.setrate ~= '' then
    RegisterKeyMapping(Config.Command.setrate, L('keymap_setrate'), 'keyboard', Config.KeyMapping.setrate)
end

if Config.KeyMapping.reset and Config.KeyMapping.reset ~= '' then
    RegisterKeyMapping(Config.Command.reset, L('keymap_reset'), 'keyboard', Config.KeyMapping.reset)
end

if Config.KeyMapping.bill and Config.KeyMapping.bill ~= '' then
    RegisterKeyMapping(Config.Command.bill, L('keymap_bill'), 'keyboard', Config.KeyMapping.bill)
end

if Config.KeyMapping.accept and Config.KeyMapping.accept ~= '' then
    RegisterKeyMapping(Config.Command.accept, L('keymap_accept'), 'keyboard', Config.KeyMapping.accept)
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
        TriggerServerEvent('taximeter:stop')
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
            TriggerServerEvent('taximeter:stop')
        end

        if inVehicle and not isDriver and not canUseMeter then
            local driverId = getDriverServerId()

            if driverId and driverId ~= lastDriverId then
                if lastDriverId then
                    TriggerServerEvent('taximeter:passengerLeft', lastDriverId)
                end

                lastDriverId = driverId
                currentDriverId = driverId
                passengerAgreed = false
                waitingAccept = false
                rideBilled = false
                TriggerServerEvent('taximeter:passengerEntered', driverId)
            elseif not driverId and lastDriverId then
                TriggerServerEvent('taximeter:passengerLeft', lastDriverId)
                lastDriverId = nil
                currentDriverId = nil
                passengerAgreed = false
                waitingAccept = false
                SendNUIMessage({ action = 'hideAccept' })
            end
        elseif wasPassenger and lastDriverId then
            TriggerServerEvent('taximeter:passengerLeft', lastDriverId)
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
                TriggerServerEvent('taximeter:passengerLeft', lastDriverId)
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

