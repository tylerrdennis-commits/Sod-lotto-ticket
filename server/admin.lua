--[[
    Lottery Commission (admin) panel. Every event re-checks permission
    server-side; the client merely displays what the server sends.
]]

local function payload(src)
    local s, st = Economy.settings, Economy.state
    local tickets, players = DB.entryStats(st.period)
    local L_ = DB.ledgerTotals()
    local jackpotPaid = DB.jackpotPaidTotal()
    local paidOut = L_.instant_paid + jackpotPaid
    local platesList = {}
    for _, id in ipairs(PlateOrder) do
        platesList[#platesList + 1] = { id = id, label = Plates[id].label, jackpot = Plates[id].jackpot }
    end
    return {
        settings = s,
        defaults = Config.Defaults,
        basePrice = Config.basePrice,
        limits = Config.Limits,
        plates = platesList,
        framework = Bridge.name,
        persistence = DB.online and 'oxmysql' or 'memory',
        analysis = Economy.analyse(s, st.pot),
        state = {
            pot = st.pot, period = st.period, lastDraw = st.lastDraw,
            nextDraw = Jackpot.nextDrawAt(), entries = tickets, entrants = players,
            serverTime = os.time(),
        },
        ledger = {
            sold = L_.sold, moneyIn = L_.money_in, houseRetained = L_.house,
            jackpotFed = L_.jackpot_fed, backing = L_.backing,
            instantPaid = L_.instant_paid, jackpotPaid = jackpotPaid, paidOut = paidOut,
            seedsInjected = st.seedsInjected or 0,
            netRemoved = L_.money_in - paidOut,
            actualRtp = L_.money_in > 0 and (paidOut / L_.money_in * 100) or 0,
        },
        winners = DB.recentWinners(Config.Admin.recentWinnersShown),
    }
end

local function send(src, extra)
    local p = payload(src)
    if extra then for k, v in pairs(extra) do p[k] = v end end
    TriggerClientEvent('sod_lottery:client:adminData', src, p)
end

local function allowed(src)
    if not Guard(src) then return false end
    if not Bridge.isAdmin(src) then
        Notify(src, L('notAdmin'), 'error')
        return false
    end
    return true
end

RegisterCommand(Config.Admin.command, function(src)
    if src <= 0 then print('[sod_lottery] the Commission panel is in-game only') return end
    if not allowed(src) then return end
    TriggerClientEvent('sod_lottery:client:openAdmin', src)
    send(src)
end, false)

RegisterNetEvent('sod_lottery:server:adminRefresh', function()
    local src = source
    if not allowed(src) then return end
    send(src)
end)

RegisterNetEvent('sod_lottery:server:adminSave', function(data)
    local src = source
    if not allowed(src) then return end
    local cleaned, err = Economy.validate(data)
    if not cleaned then
        send(src, { message = L('invalid', err), messageKind = 'error' })
        return
    end
    -- if the seed was raised and the pot is below it, top the pot up to the new seed
    local newSeed = Economy.seedValue(cleaned)   -- seed at the new ticket price
    if Economy.state.pot < newSeed then
        Economy.state.seedsInjected = (Economy.state.seedsInjected or 0) + (newSeed - Economy.state.pot)
        Economy.state.pot = newSeed
        Economy.saveState()
    end
    Economy.saveSettings(cleaned)
    print(('[sod_lottery] settings changed by %s (%s)'):format(GetPlayerName(src) or '?', Bridge.getIdentifier(src) or src))
    TriggerClientEvent('sod_lottery:client:config', -1, { price = cleaned.ticketPrice, salesEnabled = cleaned.salesEnabled })
    send(src, { message = L('saved'), messageKind = 'ok' })
end)

RegisterNetEvent('sod_lottery:server:adminDrawNow', function(ignoreMin)
    local src = source
    if not allowed(src) then return end
    local ok, msg = Jackpot.draw(ignoreMin == true)
    print(('[sod_lottery] manual draw by %s: %s'):format(GetPlayerName(src) or '?', msg))
    send(src, { message = msg, messageKind = ok and 'ok' or 'error' })
end)

RegisterNetEvent('sod_lottery:server:adminRestoreDefaults', function()
    local src = source
    if not allowed(src) then return end
    DB.deleteKV('settings')
    Economy.saveSettings(assert(Economy.validate(Economy.deepcopy(Config.Defaults))))
    send(src, { message = L('saved'), messageKind = 'ok' })
end)
