# TaxiJob

ESX Legacy Taxi-Job mit Taxameter, Passagier-Zustimmung, Trinkgeld und Fahrtenbuch.

## Anforderungen

| Resource | Pflicht | Hinweis |
|----------|---------|---------|
| [es_extended](https://github.com/esx-framework/esx_core) | Ja | ESX Legacy 1.10+ |
| [oxmysql](https://github.com/overextended/oxmysql) | Ja | Fahrtenbuch |
| [esx_addonaccount](https://github.com/esx-framework/esx_addonaccount) | Empfohlen | Firmenkasse `society_taxi` |
| [esx_society](https://github.com/esx-framework/esx_society) | Empfohlen | Society-Menü |
| [esx_skin](https://github.com/esx-framework/esx_skin) + skinchanger | Empfohlen | Umkleide |
| [esx_context](https://github.com/esx-framework/esx_context) | Empfohlen | Menüs (Fallback: esx_menu_default) |
| esx_menu_default | Optional | Menü-Fallback ohne esx_context |

## Installation

1. Ordner als `TaxiJob` nach `resources/` kopieren.
2. SQL ausführen: `sql/install.sql`
3. Falls der Job **taxi** noch nicht existiert, SQL aus `esx_taxijob/localization/de_esx_taxijob.sql` importieren (oder `esx_taxijob` einmal starten).
4. In `server.cfg` **nach** `es_extended` und `oxmysql`:

```cfg
ensure es_extended
ensure oxmysql
ensure esx_addonaccount
ensure esx_society
ensure esx_skin
ensure esx_context
ensure esx_menu_default

# Standard-Taxi-Job ersetzen:
stop esx_taxijob
ensure TaxiJob
```

5. `config.lua` anpassen (Job-Name, Zonen, Preise, Sprache).

## Sprache / Locale

In `config.lua`:

```lua
Config.Locale = 'de' -- oder 'en'
```

Übersetzungen liegen in `locales/de.lua` und `locales/en.lua`.  
Neue Texte: Key in beiden Dateien eintragen, im Code mit `L('key')` oder `L('key', arg1, arg2)` nutzen.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| `/taxirate` | Preis pro km (Fahrer) |
| `/taxireset` | Taxameter zurücksetzen |
| `/taxibill` | Fahrt abrechnen |
| `/taxizustimmen` oder **Y** | Tarif akzeptieren (Passagier) |
| **F6** | Taxi-Menü (Job) |

## Konfiguration

- `Config.JobName` – Standard: `taxi`
- `Config.SocietyName` – Standard: `society_taxi`
- `Config.Notify` – `auto` (ESX), `ox_lib` oder in `Config.Functions` eigene Funktion
- `Config.PaymentAccount` – `money` oder `bank`

## Deinstallation

```cfg
stop TaxiJob
ensure esx_taxijob
```

Tabelle `taxijob_trips` optional per Hand löschen.

## Support

Bei Problemen: ESX-Konsole auf Fehler prüfen, `society_taxi` in der Datenbank und Job `taxi` vorhanden?
