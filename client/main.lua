--[[
    Client: purely presentation. Opens the NUI ticket / Commission panel and
    relays NUI callbacks to the server. No outcomes are decided here.
]]

local ticketOpen, adminOpen = false, false
local price, salesEnabled = Config.Defaults.ticketPrice, true

local function focus()
    SetNuiFocus(ticketOpen or adminOpen, ticketOpen or adminOpen)
end

---------------------------------------------------------------------------
-- Server -> client
---------------------------------------------------------------------------
RegisterNetEvent('sod_lottery:client:openTicket', function(data)
    ticketOpen = true
    focus()
    SendNUIMessage({ action = 'openTicket', data = data })
end)

RegisterNetEvent('sod_lottery:client:reopen', function()
    TriggerServerEvent('sod_lottery:server:reopen')
end)

RegisterNetEvent('sod_lottery:client:claimResult', function(result)
    SendNUIMessage({ action = 'result', data = result })
end)

RegisterNetEvent('sod_lottery:client:notify', function(n)
    SendNUIMessage({ action = 'toast', data = { text = n.text, kind = n.kind, ms = Config.UI.toastMs } })
end)

RegisterNetEvent('sod_lottery:client:telegram', function(t)
    t.ms = Config.UI.telegramMs
    SendNUIMessage({ action = 'telegram', data = t })
end)

RegisterNetEvent('sod_lottery:client:config', function(c)
    price, salesEnabled = c.price, c.salesEnabled
end)

RegisterNetEvent('sod_lottery:client:openAdmin', function()
    adminOpen = true
    focus()
    SendNUIMessage({ action = 'openAdmin' })
end)

RegisterNetEvent('sod_lottery:client:adminData', function(data)
    if not adminOpen then return end
    SendNUIMessage({ action = 'adminData', data = data })
end)

---------------------------------------------------------------------------
-- NUI -> client -> server
---------------------------------------------------------------------------
RegisterNUICallback('claim', function(data, cb)
    if type(data) == 'table' and data.serial then
        TriggerServerEvent('sod_lottery:server:claim', tostring(data.serial):sub(1, 12))
    end
    cb({ ok = true })
end)

RegisterNUICallback('closeTicket', function(_, cb)
    ticketOpen = false
    focus()
    cb({ ok = true })
end)

RegisterNUICallback('closeAdmin', function(_, cb)
    adminOpen = false
    focus()
    cb({ ok = true })
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    TriggerServerEvent('sod_lottery:server:adminRefresh')
    cb({ ok = true })
end)

RegisterNUICallback('adminSave', function(data, cb)
    TriggerServerEvent('sod_lottery:server:adminSave', data) -- validated server-side
    cb({ ok = true })
end)

RegisterNUICallback('adminDrawNow', function(data, cb)
    TriggerServerEvent('sod_lottery:server:adminDrawNow', type(data) == 'table' and data.ignoreMin == true)
    cb({ ok = true })
end)

RegisterNUICallback('adminRestoreDefaults', function(_, cb)
    TriggerServerEvent('sod_lottery:server:adminRestoreDefaults')
    cb({ ok = true })
end)

---------------------------------------------------------------------------
-- Lottery counters (optional world locations)
---------------------------------------------------------------------------
local function drawText3D(coords, text)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z + 0.25)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextColor(240, 225, 190, 230)
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 255)
    DisplayText(CreateVarString(10, 'LITERAL_STRING', text), x, y)
end

CreateThread(function()
    -- tell the server we are in, so held winnings can be paid out
    while not NetworkIsPlayerActive(PlayerId()) do Wait(1000) end
    Wait(8000)
    TriggerServerEvent('sod_lottery:server:ready')

    local dp = Config.DirectSale
    if not (dp.enabled and dp.useLocations and #dp.locations > 0) then return end
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        for _, loc in ipairs(dp.locations) do
            local dist = #(pos - loc.coords)
            if dist < 12.0 then sleep = 0 end
            if dist < dp.interactDistance and salesEnabled and not ticketOpen and not adminOpen then
                drawText3D(loc.coords, L('pressToBuy', tostring(price)))
                if IsControlJustReleased(0, dp.interactKey) then
                    TriggerServerEvent('sod_lottery:server:buy')
                    Wait(1500)
                end
            end
        end
        Wait(sleep)
    end
end)

-- Chat suggestions for the admin money commands (the commands themselves are
-- permission-checked on the server; suggestions are harmless for others).
CreateThread(function()
    local am = Config.AdminMoney
    if not (am and am.enabled and am.chatSuggestions) then return end
    Wait(2000)
    local params = { { name = 'playerId', help = 'Server ID of the player' }, { name = 'amount', help = ('Cash amount (max $%s, 2 decimals)'):format(am.maxAmount) } }
    TriggerEvent('chat:addSuggestion', '/' .. am.giveCommand, 'Lottery Commission: give cash to a player', params)
    TriggerEvent('chat:addSuggestion', '/' .. am.takeCommand, 'Lottery Commission: take cash from a player', params)
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and (ticketOpen or adminOpen) then
        SetNuiFocus(false, false)
    end
end)
