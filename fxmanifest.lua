-- State of Deliverance Territorial Lottery
-- A scratch-ticket money sink with a progressive jackpot draw.
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

name 'sod_lottery'
author 'State of Deliverance'
description 'Deliverance Seed & Fortune - Territorial scratch-ticket lottery with progressive jackpot'
version '1.0.0'

shared_scripts {
    'shared/config.lua',
    'locales/strings.lua',
    'shared/plates.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/db.lua',
    'server/bridge.lua',
    'server/economy.lua',
    'server/main.lua',
    'server/jackpot.lua',
    'server/admin.lua',
    'server/money_admin.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/sounds/win.wav',
    'html/sounds/fart.wav',
    'html/sounds/sadtrombone.wav',
    'html/sounds/yeehaw.wav',
    'html/sounds/scratch.wav',
}

-- oxmysql is optional (in-memory fallback), but strongly recommended for persistence.
-- Start it BEFORE this resource in server.cfg.
