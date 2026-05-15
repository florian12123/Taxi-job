fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'AngelV'
description 'ESX Legacy Taxi-Job – Taxameter, Garage, NPC-Fahrten, Trinkgeld & Fahrtenbuch'
version '2.2.0'

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
    'shared/notify.lua',
}

client_scripts {
    'client/menu.lua',
    'client/job.lua',
    'client/npc.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/job.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

dependencies {
    'es_extended',
    'oxmysql',
}

-- Empfohlen (Standard ESX Legacy Stack):
-- esx_addonaccount, esx_society, esx_skin, skinchanger, esx_context, esx_menu_default

exports {
    'ResetTaximeter',
}
