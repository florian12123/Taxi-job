local function isEnabled()
    return Config.TripLog and Config.TripLog.enabled ~= false
end

MySQL.ready(function()
    if not isEnabled() then
        return
    end

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS av_taxijob_trips (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT,
            driver_identifier VARCHAR(60) NOT NULL,
            driver_name VARCHAR(64) NOT NULL,
            passenger_identifier VARCHAR(60) DEFAULT NULL,
            passenger_name VARCHAR(64) DEFAULT NULL,
            distance_km DECIMAL(10, 3) NOT NULL DEFAULT 0,
            fare DECIMAL(10, 2) NOT NULL DEFAULT 0,
            tip DECIMAL(10, 2) NOT NULL DEFAULT 0,
            total DECIMAL(10, 2) NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_driver (driver_identifier),
            KEY idx_created (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end)

---@param data table
---@return number|nil tripId
function LogTaxiTrip(data)
    if not isEnabled() or not data then
        return nil
    end

    local fare = tonumber(data.fare) or 0
    local tip = tonumber(data.tip) or 0
    local total = tonumber(data.total) or (fare + tip)

    return MySQL.insert.await([[
        INSERT INTO av_taxijob_trips
            (driver_identifier, driver_name, passenger_identifier, passenger_name, distance_km, fare, tip, total)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.driverIdentifier,
        data.driverName or 'Unbekannt',
        data.passengerIdentifier,
        data.passengerName or 'Unbekannt',
        tonumber(data.distanceKm) or 0,
        fare,
        tip,
        total,
    })
end

function UpdateTripTip(tripId, tip, total)
    if not isEnabled() or not tripId then
        return
    end

    MySQL.update.await('UPDATE av_taxijob_trips SET tip = ?, total = ? WHERE id = ?', {
        tip,
        total,
        tripId,
    })
end

function GetDriverTrips(identifier, limit)
    if not isEnabled() then
        return {}
    end

    limit = math.min(tonumber(limit) or 25, 50)

    return MySQL.query.await([[
        SELECT id, passenger_name, distance_km, fare, tip, total, created_at
        FROM av_taxijob_trips
        WHERE driver_identifier = ?
        ORDER BY created_at DESC
        LIMIT ?
    ]], { identifier, limit }) or {}
end
