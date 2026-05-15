local ESX = exports['es_extended']:getSharedObject()
local sessions = {}
local pendingTips = {}

local function isTaxiJob(xPlayer)
    return xPlayer and xPlayer.job and xPlayer.job.name == Config.JobName
end

local function getSession(src)
    return sessions[src]
end

local function clearSession(src)
    sessions[src] = nil
end

local function clampRate(rate)
    rate = tonumber(rate) or Config.DefaultPricePerKm
    if rate < Config.MinPricePerKm then
        rate = Config.MinPricePerKm
    elseif rate > Config.MaxPricePerKm then
        rate = Config.MaxPricePerKm
    end
    return ESX.Math.Round(rate, 2)
end

local function hasAgreedPassenger(session)
    if not session or not session.agreedPassengers then
        return false
    end

    for _ in pairs(session.agreedPassengers) do
        return true
    end

    return false
end

local function countAgreedPassengers(session)
    local count = 0
    if session.agreedPassengers then
        for _ in pairs(session.agreedPassengers) do
            count = count + 1
        end
    end
    return count
end

local function getDriverInVehicle(vehicle)
    if not vehicle or vehicle == 0 then
        return nil
    end

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local ped = GetPlayerPed(xPlayer.source)
        if ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) == vehicle then
            if GetPedInVehicleSeat(vehicle, -1) == ped then
                return xPlayer.source
            end
        end
    end

    return nil
end

local function getPassengersInVehicle(driverSrc)
    local driverPed = GetPlayerPed(driverSrc)
    if not driverPed or driverPed == 0 then
        return {}
    end

    local vehicle = GetVehiclePedIsIn(driverPed, false)
    if not vehicle or vehicle == 0 then
        return {}
    end

    local passengers = {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local src = xPlayer.source
        if src ~= driverSrc then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) == vehicle then
                passengers[#passengers + 1] = src
            end
        end
    end

    return passengers
end

local function maxAllowedFare(session)
    if not session then
        return 0
    end

    local rate = session.pricePerKm or Config.DefaultPricePerKm
    local elapsed = (os.time() - session.startedAt) + 1
    local maxByTime = Config.BaseFare + (elapsed / 60) * 200 * rate
    return math.max(Config.BaseFare, maxByTime)
end

local function calculateFare(session)
    if not session.meterStarted then
        return 0
    end

    local km = session.distanceMeters / 1000.0
    local rate = session.pricePerKm or Config.DefaultPricePerKm

    if Config.ChargeOnlyWhileDriving and km <= 0 then
        return 0
    end

    local fare = Config.BaseFare + (km * rate)
    return ESX.Math.Round(math.max(fare, 0), 2)
end

local function buildPayload(session)
    return {
        active = session.active,
        meterStarted = session.meterStarted or false,
        fare = calculateFare(session),
        distanceKm = session.distanceMeters / 1000.0,
        isDriving = session.isDriving or false,
        baseFare = Config.BaseFare,
        pricePerKm = session.pricePerKm or Config.DefaultPricePerKm,
        acceptKey = Config.KeyMapping.accept or 'Y',
        pendingPassengers = session.pendingPassengers or 0,
        agreedCount = countAgreedPassengers(session),
    }
end

local function payDriverShare(xDriver, amount, reason)
    local societyShare = ESX.Math.Round(amount * (Config.SocietyPercent / 100), 2)
    local driverShare = amount - societyShare

    if GetResourceState('esx_addonaccount') ~= 'started' then
        xDriver.addMoney(amount, reason or 'Taxi')
        return amount, 0
    end

    TriggerEvent('esx_addonaccount:getSharedAccount', Config.SocietyName, function(societyAccount)
        if societyAccount then
            societyAccount.addMoney(societyShare)
            xDriver.addMoney(driverShare, reason or 'Taxi')
        else
            xDriver.addMoney(amount, reason or 'Taxi')
        end
    end)

    return driverShare, societyShare
end

local function chargePlayer(xTarget, amount, reason)
    local account = Config.PaymentAccount or 'money'
    local balance

    if account == 'money' then
        balance = xTarget.getMoney()
    else
        local acc = xTarget.getAccount(account)
        balance = acc and acc.money or 0
    end

    if balance < amount then
        return false
    end

    if account == 'money' then
        xTarget.removeMoney(amount, reason or 'Taxi')
    else
        xTarget.removeAccountMoney(account, amount, reason or 'Taxi')
    end

    return true
end

local function isPassengerBilled(session, passengerSrc)
    return session and session.billedPassengers and session.billedPassengers[passengerSrc] == true
end

local function clearPassengerBilling(session, passengerSrc)
    if session and session.billedPassengers then
        session.billedPassengers[passengerSrc] = nil
    end
end

local function syncToVehicleOccupants(driverSrc, payload)
    local driverPed = GetPlayerPed(driverSrc)
    if not driverPed or driverPed == 0 then
        return
    end

    local vehicle = GetVehiclePedIsIn(driverPed, false)
    if not vehicle or vehicle == 0 then
        return
    end

    local session = sessions[driverSrc]

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local targetSrc = xPlayer.source
        if targetSrc ~= driverSrc then
            local targetPed = GetPlayerPed(targetSrc)
            if targetPed and targetPed ~= 0 and GetVehiclePedIsIn(targetPed, false) == vehicle then
                local agreed = session and session.agreedPassengers and session.agreedPassengers[targetSrc]
                local billed = session and isPassengerBilled(session, targetSrc)

                local syncPayload = {}
                for key, value in pairs(payload) do
                    syncPayload[key] = value
                end
                syncPayload.passengerAgreed = agreed or false
                syncPayload.needsAccept = session and session.active and not agreed and not billed
                syncPayload.rideBilled = billed or false
                TriggerClientEvent('taximeter:syncDisplay', targetSrc, syncPayload, driverSrc)
            end
        end
    end
end

local function pushSessionState(driverSrc)
    local session = getSession(driverSrc)
    if not session then
        return
    end

    local payload = buildPayload(session)
    TriggerClientEvent('taximeter:sessionState', driverSrc, payload)
    syncToVehicleOccupants(driverSrc, payload)
end

local function requestPassengerAccept(driverSrc, passengerSrc)
    local session = getSession(driverSrc)
    if not session or not session.active then
        return
    end

    if session.agreedPassengers[passengerSrc] then
        return
    end

    if isPassengerBilled(session, passengerSrc) then
        return
    end

    local payload = buildPayload(session)
    payload.needsAccept = true
    payload.passengerAgreed = false

    TriggerClientEvent('taximeter:requestAccept', passengerSrc, payload, driverSrc)
end

local function requestAllPassengersAccept(driverSrc)
    local passengers = getPassengersInVehicle(driverSrc)
    local session = getSession(driverSrc)

    if not session then
        return
    end

    session.pendingPassengers = 0

    for i = 1, #passengers do
        local passengerSrc = passengers[i]
        if not session.agreedPassengers[passengerSrc] and not isPassengerBilled(session, passengerSrc) then
            session.pendingPassengers = session.pendingPassengers + 1
            requestPassengerAccept(driverSrc, passengerSrc)
        end
    end

    if session.pendingPassengers > 0 then
        Config.Functions.serverNotify(driverSrc, L('driver_passenger_waiting'), 'info')
    end
end

local function clearAgreements(session)
    session.agreedPassengers = {}
    session.billedPassengers = {}
    session.meterStarted = false
    session.distanceMeters = 0.0
    session.lastPos = nil
    session.isDriving = false
    session.startedAt = os.time()
end

local function createWaitingSession(src, pricePerKm)
    sessions[src] = {
        active = true,
        meterStarted = false,
        startedAt = os.time(),
        distanceMeters = 0.0,
        lastPos = nil,
        isDriving = false,
        pricePerKm = clampRate(pricePerKm),
        agreedPassengers = {},
        billedPassengers = {},
        pendingPassengers = 0,
    }

    Config.Functions.serverNotify(src, L('rate_set', sessions[src].pricePerKm), 'success')
    Config.Functions.serverNotify(src, L('waiting_passenger'), 'info')

    pushSessionState(src)

    local passengers = getPassengersInVehicle(src)
    if #passengers > 0 then
        requestAllPassengersAccept(src)
    end
end

local function startMeterForDriver(driverSrc)
    local session = getSession(driverSrc)
    if not session or not hasAgreedPassenger(session) then
        return
    end

    session.meterStarted = true
    session.startedAt = os.time()
    session.distanceMeters = 0.0
    session.lastPos = nil
    session.isDriving = false

    Config.Functions.serverNotify(driverSrc, L('meter_started'), 'success')

    local payload = buildPayload(session)
    TriggerClientEvent('taximeter:meterStarted', driverSrc, payload)
    syncToVehicleOccupants(driverSrc, payload)
end

RegisterNetEvent('taximeter:setRate', function(pricePerKm)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)

    if not isTaxiJob(xPlayer) then
        Config.Functions.serverNotify(src, L('no_job'), 'error')
        return
    end

    local rate = tonumber(pricePerKm)
    if not rate or rate < Config.MinPricePerKm or rate > Config.MaxPricePerKm then
        Config.Functions.serverNotify(src, L('rate_invalid', Config.MinPricePerKm, Config.MaxPricePerKm), 'error')
        return
    end

    local session = getSession(src)

    if not session then
        createWaitingSession(src, rate)
        return
    end

    local wasRunning = session.meterStarted
    session.pricePerKm = clampRate(rate)
    clearAgreements(session)

    Config.Functions.serverNotify(src, L('rate_set', session.pricePerKm), 'success')

    if wasRunning or #getPassengersInVehicle(src) > 0 then
        Config.Functions.serverNotify(src, L('rate_changed_reaccept'), 'info')
        requestAllPassengersAccept(src)
    else
        Config.Functions.serverNotify(src, L('waiting_passenger'), 'info')
    end

    pushSessionState(src)
end)

RegisterNetEvent('taximeter:stop', function()
    local src = source
    local session = getSession(src)
    if not session then
        return
    end

    local payload = buildPayload(session)
    payload.active = false

    TriggerClientEvent('taximeter:sessionState', src, payload)
    syncToVehicleOccupants(src, payload)
    clearSession(src)
end)

RegisterNetEvent('taximeter:reset', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)

    if not isTaxiJob(xPlayer) then
        return
    end

    local session = getSession(src)
    if not session then
        return
    end

    local rate = session.pricePerKm
    local wasStarted = session.meterStarted
    local agreed = session.agreedPassengers or {}

    session.distanceMeters = 0.0
    session.lastPos = nil
    session.isDriving = false
    session.startedAt = os.time()
    session.agreedPassengers = agreed
    session.meterStarted = wasStarted and hasAgreedPassenger(session)

    Config.Functions.serverNotify(src, L('meter_reset'), 'info')
    pushSessionState(src)
end)

RegisterNetEvent('taximeter:updatePosition', function(coords, isDriving)
    local src = source
    local session = getSession(src)

    if not session or not session.active or not coords then
        return
    end

    session.isDriving = isDriving == true

    if not session.meterStarted or not hasAgreedPassenger(session) then
        local payload = buildPayload(session)
        TriggerClientEvent('taximeter:updateDisplay', src, payload)
        syncToVehicleOccupants(src, payload)
        return
    end

    local pos = vector3(coords.x, coords.y, coords.z)

    if isDriving and session.lastPos then
        local delta = #(pos - session.lastPos)
        if delta > 0.0 and delta < 150.0 then
            session.distanceMeters = session.distanceMeters + delta
        end
    end

    if isDriving or not Config.ChargeOnlyWhileDriving then
        session.lastPos = pos
    end

    local payload = buildPayload(session)
    TriggerClientEvent('taximeter:updateDisplay', src, payload)
    syncToVehicleOccupants(src, payload)
end)

RegisterNetEvent('taximeter:passengerEntered', function(driverServerId)
    local src = source
    local driver = tonumber(driverServerId)
    local session = getSession(driver)

    if not session or not session.active then
        Config.Functions.serverNotify(src, L('no_driver_rate'), 'error')
        TriggerClientEvent('taximeter:promptRate', driver)
        return
    end

    clearPassengerBilling(session, src)

    if not session.agreedPassengers[src] and not isPassengerBilled(session, src) then
        session.pendingPassengers = (session.pendingPassengers or 0) + 1
        requestPassengerAccept(driver, src)
        Config.Functions.serverNotify(driver, L('driver_passenger_waiting'), 'info')
    end
end)

RegisterNetEvent('taximeter:passengerAgree', function(driverServerId)
    local src = source
    local driver = tonumber(driverServerId)
    local session = getSession(driver)

    if not session or not session.active then
        Config.Functions.serverNotify(src, L('not_in_taxi_passenger'), 'error')
        return
    end

    local driverPed = GetPlayerPed(driver)
    local passengerPed = GetPlayerPed(src)

    if not driverPed or driverPed == 0 or not passengerPed or passengerPed == 0 then
        return
    end

    local vehicle = GetVehiclePedIsIn(driverPed, false)
    if vehicle == 0 or GetVehiclePedIsIn(passengerPed, false) ~= vehicle then
        Config.Functions.serverNotify(src, L('not_in_taxi_passenger'), 'error')
        return
    end

    if isPassengerBilled(session, src) then
        Config.Functions.serverNotify(src, L('ride_already_billed'), 'info')
        return
    end

    if session.agreedPassengers[src] then
        Config.Functions.serverNotify(src, L('already_accepted'), 'info')
        return
    end

    session.agreedPassengers[src] = true
    session.pendingPassengers = math.max((session.pendingPassengers or 1) - 1, 0)

    Config.Functions.serverNotify(src, L('passenger_accepted'), 'success')
    Config.Functions.serverNotify(driver, L('driver_passenger_accepted'), 'success')

    if not session.meterStarted then
        startMeterForDriver(driver)
    else
        pushSessionState(driver)
    end

    local payload = buildPayload(session)
    payload.needsAccept = false
    payload.passengerAgreed = true

    TriggerClientEvent('taximeter:acceptConfirmed', src, payload)
end)

RegisterNetEvent('taximeter:passengerLeft', function(driverServerId)
    local src = source
    local driver = tonumber(driverServerId)
    local session = getSession(driver)

    if not session then
        return
    end

    if session.agreedPassengers[src] then
        session.agreedPassengers[src] = nil
    end

    clearPassengerBilling(session, src)

    if session.pendingPassengers and session.pendingPassengers > 0 then
        session.pendingPassengers = session.pendingPassengers - 1
    end

    TriggerClientEvent('taximeter:hideAccept', src)

    if not hasAgreedPassenger(session) then
        session.meterStarted = false
        session.distanceMeters = 0.0
        session.lastPos = nil
        Config.Functions.serverNotify(driver, L('meter_paused_no_passenger'), 'info')
    end

    pushSessionState(driver)
end)

RegisterNetEvent('taximeter:giveTip', function(driverServerId, percent)
    local src = source

    if not Config.Tips or Config.Tips.enabled == false then
        return
    end

    local pending = pendingTips[src]
    local driver = tonumber(driverServerId)

    if not pending or pending.driver ~= driver or pending.expires < os.time() then
        Config.Functions.serverNotify(src, L('tip_expired'), 'error')
        pendingTips[src] = nil
        return
    end

    percent = tonumber(percent) or 0
    local allowed = false
    for i = 1, #(Config.Tips.percents or {}) do
        if Config.Tips.percents[i] == percent then
            allowed = true
            break
        end
    end

    if not allowed or percent <= 0 then
        Config.Functions.serverNotify(src, L('tip_invalid'), 'error')
        pendingTips[src] = nil
        return
    end

    local xPassenger = ESX.GetPlayerFromId(src)
    local xDriver = ESX.GetPlayerFromId(driver)

    if not xPassenger or not xDriver then
        pendingTips[src] = nil
        return
    end

    local tipAmount = ESX.Math.Round(pending.fare * (percent / 100), 2)
    if tipAmount <= 0 then
        pendingTips[src] = nil
        return
    end

    if not chargePlayer(xPassenger, tipAmount, 'Taxi-Trinkgeld') then
        Config.Functions.serverNotify(src, L('tip_not_enough', tipAmount), 'error')
        return
    end

    local driverShare = payDriverShare(xDriver, tipAmount, 'Taxi-Trinkgeld')

    if pending.tripId then
        UpdateTripTip(pending.tripId, tipAmount, pending.fare + tipAmount)
    end

    Config.Functions.serverNotify(src, L('tip_sent', tipAmount), 'success')
    Config.Functions.serverNotify(driver, L('tip_received', tipAmount), 'success')

    pendingTips[src] = nil
end)

RegisterNetEvent('taximeter:skipTip', function(driverServerId)
    local src = source
    local pending = pendingTips[src]

    if pending and pending.driver == tonumber(driverServerId) then
        pendingTips[src] = nil
    end
end)

RegisterNetEvent('taximeter:billPassenger', function(targetServerId)
    local src = source
    local xDriver = ESX.GetPlayerFromId(src)
    local session = getSession(src)

    if not isTaxiJob(xDriver) then
        return
    end

    if not session or not session.active then
        Config.Functions.serverNotify(src, L('not_in_vehicle'), 'error')
        return
    end

    if not session.meterStarted then
        Config.Functions.serverNotify(src, L('passenger_must_accept'), 'error')
        return
    end

    local target = tonumber(targetServerId)
    if not target or target == src then
        Config.Functions.serverNotify(src, L('no_passenger'), 'error')
        return
    end

    if not session.agreedPassengers or not session.agreedPassengers[target] then
        Config.Functions.serverNotify(src, L('passenger_must_accept'), 'error')
        return
    end

    local fare = calculateFare(session)
    if fare <= 0 then
        Config.Functions.serverNotify(src, L('fare_zero'), 'error')
        return
    end

    local maxFare = maxAllowedFare(session)
    if fare > maxFare then
        fare = ESX.Math.Round(maxFare, 2)
    end

    local xTarget = ESX.GetPlayerFromId(target)
    if not xTarget then
        Config.Functions.serverNotify(src, L('no_passenger'), 'error')
        return
    end

    if not chargePlayer(xTarget, fare, 'Taxi-Fahrt') then
        Config.Functions.serverNotify(src, L('not_enough_money'), 'error')
        Config.Functions.serverNotify(target, L('billed_passenger_fail', fare), 'error')
        return
    end

    local driverShare = ESX.Math.Round(fare * ((100 - Config.SocietyPercent) / 100), 2)
    payDriverShare(xDriver, fare, 'Taxi-Fahrt')
    Config.Functions.serverNotify(src, L('billed_driver', fare, driverShare), 'success')
    Config.Functions.serverNotify(target, L('billed_passenger', fare), 'info')

    local distanceKm = session.distanceMeters / 1000.0
    local tripId = LogTaxiTrip({
        driverIdentifier = xDriver.identifier,
        driverName = xDriver.getName(),
        passengerIdentifier = xTarget.identifier,
        passengerName = xTarget.getName(),
        distanceKm = distanceKm,
        fare = fare,
        tip = 0,
        total = fare,
    })

    if Config.Tips and Config.Tips.enabled then
        pendingTips[target] = {
            driver = src,
            fare = fare,
            tripId = tripId,
            expires = os.time() + (Config.Tips.timeoutSeconds or 90),
        }

        TriggerClientEvent('taximeter:showTip', target, {
            driverId = src,
            fare = fare,
            driverName = xDriver.getName(),
            percents = Config.Tips.percents,
        })
    end

    session.billedPassengers = session.billedPassengers or {}
    session.billedPassengers[target] = true
    session.agreedPassengers[target] = nil
    session.meterStarted = false
    session.distanceMeters = 0.0
    session.lastPos = nil
    session.isDriving = false
    session.startedAt = os.time()

    TriggerClientEvent('taximeter:rideBilled', target)

    local passengers = getPassengersInVehicle(src)
    local needsNewAccept = false

    for i = 1, #passengers do
        if not isPassengerBilled(session, passengers[i]) then
            needsNewAccept = true
            break
        end
    end

    if needsNewAccept then
        requestAllPassengersAccept(src)
    else
        Config.Functions.serverNotify(src, L('waiting_passenger'), 'info')
    end

    pushSessionState(src)
end)

AddEventHandler('playerDropped', function()
    local src = source

    pendingTips[src] = nil

    for driverSrc, session in pairs(sessions) do
        if session.agreedPassengers and session.agreedPassengers[src] then
            session.agreedPassengers[src] = nil
            if not hasAgreedPassenger(session) then
                session.meterStarted = false
            end
        end
    end

    clearSession(src)
end)

AddEventHandler('esx:setJob', function(playerId, job)
    if job.name ~= Config.JobName then
        clearSession(playerId)
        TriggerClientEvent('taximeter:forceHide', playerId)
    end
end)
