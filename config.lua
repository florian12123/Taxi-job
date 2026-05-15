--[[
    TaxiJob – zentrale Einstellungen
    ───────────────────────────────────────────────────────────────────────────
    Nach Änderungen: `ensure TaxiJob` (oder Server neu starten).

    Typische Anpassungen:
    • Config.JobName / SocietyName – müssen zur Datenbank (jobs, addon_account) passen
    • Config.Zones – Garage, Spawn, Einparken, Umkleide
    • Config.AllowedVehicles – welche Fahrzeuge das Taxameter nutzen dürfen
    • Abschnitt „Taxameter“ – Grundtarif, $/km, Min/Max, wie Strecke gezählt wird
--]]

Config = {}

--------------------------------------------------------------------------------
-- 1. Sprache
--------------------------------------------------------------------------------
-- `de` → locales/de.lua   |   `en` → locales/en.lua
Config.Locale = 'de'

--------------------------------------------------------------------------------
-- 2. Mitteilungen (Notifications)
--------------------------------------------------------------------------------
-- 'auto'   = ESX ShowNotification
-- 'ox_lib' = ox_lib (nur wenn Resource läuft)
-- 'custom' = eigene Logik in Config.Functions unten
Config.Notify = 'auto'

--------------------------------------------------------------------------------
-- 3. Job & Firma (ESX)
--------------------------------------------------------------------------------
-- Name des Jobs in der DB (z. B. jobs.name = 'taxi')
Config.JobName = 'taxi'

-- Firmenkonto (z. B. esx_addonaccount: society_taxi)
Config.SocietyName = 'society_taxi'

-- Anteil für die Firma von Fahrt + Trinkgeld, in % (0–100).
-- Beispiel 30 → Fahrer 70 %, Firma 30 %
Config.SocietyPercent = 30

-- Womit Passagiere bezahlen: Bargeld oder Bank (Konto muss bei ESX existieren)
Config.PaymentAccount = 'money' -- 'money' | 'bank'

--------------------------------------------------------------------------------
-- 4. Taxi-HQ: Marker & Koordinaten (Standard: Downtown Taxi, ESX Legacy)
--------------------------------------------------------------------------------
-- Ab diesem Abstand werden Marker gerendert (Meter)
Config.DrawDistance = 10.0

--[[
    Zonen:
      VehicleSpawner    – Hier E drücken → Fahrzeug wählen / spawnen
      VehicleSpawnPoint – Fahrzeug erscheint hier (Heading = Blickrichtung)
      VehicleDeleter    – Taxi einparken (E im Fahrersitz)
      Cloakroom         – Umkleide (nutzt esx_skin + skinchanger)

      Type -1 beim Spawnpunkt = kein sichtbarer Marker, nur Platz-Check für „in Zone“.
--]]
Config.Zones = {
    VehicleSpawner = {
        Pos = vector3(915.039, -162.187, 74.5),
        Size = vector3(1.0, 1.0, 1.0),
        Color = { r = 204, g = 204, b = 0 },
        Type = 36,
        Rotate = true,
    },
    VehicleSpawnPoint = {
        Pos = vector3(911.108, -177.867, 74.283),
        Size = vector3(1.5, 1.5, 1.0),
        Type = -1,
        Rotate = false,
        Heading = 225.0,
    },
    VehicleDeleter = {
        Pos = vector3(908.317, -183.070, 73.201),
        Size = vector3(3.0, 3.0, 0.25),
        Color = { r = 255, g = 0, b = 0 },
        Type = 1,
        Rotate = false,
    },
    Cloakroom = {
        Pos = vector3(894.88, -180.23, 74.5),
        Size = vector3(1.0, 1.0, 1.0),
        Color = { r = 204, g = 204, b = 0 },
        Type = 21,
        Rotate = true,
    },
}

--------------------------------------------------------------------------------
-- 5. Erlaubte Taxi-Modelle
--------------------------------------------------------------------------------
-- Nur diese Spawn-Namen aktivieren das Taxameter (+ Job-Menü in erlaubten Fahrzeugen).
-- `title` erscheint im Garagen-Menü.
-- Config.VehicleModels wird automatisch aus dieser Liste gefüllt.
Config.AllowedVehicles = {
    { model = 'taxi', title = 'Taxi' },
    { model = 'taxiold', title = 'Taxi Classic' },
    { model = 'dynasty2', title = 'Dynasty' },
}

Config.VehicleModels = {}
for i = 1, #Config.AllowedVehicles do
    Config.VehicleModels[i] = Config.AllowedVehicles[i].model
end

--------------------------------------------------------------------------------
-- 6. Taxameter – Berechnung
--------------------------------------------------------------------------------
-- Grundtarif (wird angezeigt sobald gefahren wird / beim Zustimmungs-Dialog)
Config.BaseFare = 5.0

-- Vorschlagswert für „Preis pro km“ (/taxirate, NUI)
Config.DefaultPricePerKm = 12.0

-- Erlaubter Bereich für $/km (Server & NUI)
Config.MinPricePerKm = 5.0
Config.MaxPricePerKm = 50.0

-- Ab dieser Fahrzeuggeschwindigkeit (km/h ≈ GTA * 3.6) gilt „es fährt“
Config.DrivingSpeedKmh = 5.0

-- true = Strecke zählt nur bei Geschwindigkeit >= DrivingSpeedKmh
-- false = (selten) anderes Kilometer-Verhalten je nach Patch
Config.ChargeOnlyWhileDriving = true

-- Aktualisierungsrate Fahrer → Server für Position/Strecke (Millisekunden)
Config.UpdateIntervalMs = 1000

-- true = beim Einsteigen ins erlaubte Taxi automatisch Tarif-Dialog einmal öffnen
Config.AutoStartMeter = true

-- „Vorauss. Ende“: Schätzung = gefahren + Luftlinie zum eigenen GPS-Wegpunkt
-- Ohne gesetzten Waypoint kein geschätzter Endpreis
Config.EstimatedFare = {
    enabled = true,
}

--------------------------------------------------------------------------------
-- 7. Fahrtenbuch (DB) & Trinkgeld nach Abrechnung
--------------------------------------------------------------------------------
Config.TripLog = {
    enabled = true, -- false = keine DB-Einträge, Menüpunkt ohne Datenaufbau durch Resource
    menuLimit = 15, -- max. Zeilen im F6-Menü „Fahrtenbuch“
}

Config.Tips = {
    enabled = true, -- Fenster nach /taxibill
    percents = { 5, 10, 20 }, -- frei wählbar, Server akzeptiert nur diese Werte
    timeoutSeconds = 90,
}

--------------------------------------------------------------------------------
-- 8. Befehle & Tasten
--------------------------------------------------------------------------------
--[[
    Command     = Chat-Befehl ohne /
    KeyMapping  = Taste in FiveM; '' = keine Taste, nur über Chat

    Hinweis: `accept` und Taste Y sollten zusammenpassen (Passagier).
--]]
Config.Command = {
    setrate = 'taxirate',
    reset = 'taxireset',
    bill = 'taxibill',
    accept = 'taxizustimmen',
}

Config.KeyMapping = {
    setrate = '',
    reset = '',
    bill = '',
    accept = 'Y',
    menu = 'F6',
}

--------------------------------------------------------------------------------
-- 9. Hooks (bei Config.Notify = 'custom')
--------------------------------------------------------------------------------
Config.Functions = {
    notify = function(msg, nType)
        if Config.Notify == 'custom' then
            return
        end
        TaxiNotify(msg, nType)
    end,
    serverNotify = function(player, msg, nType)
        if Config.Notify == 'custom' then
            return
        end
        TaxiNotifyServer(player, msg, nType)
    end,
}
