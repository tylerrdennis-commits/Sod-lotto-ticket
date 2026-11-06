--[[
    Progressive jackpot draw.
    Every ticket sold adds one entry for the current period. When the draw is
    due (every N hours, or at scheduled daily times) and the minimum players /
    tickets are met, one entry is drawn uniformly at random (server RNG), the
    whole pot is paid (or queued if the winner is offline), a telegram goes out
    to the territory, and the pot is reseeded. If the minimums are not met the
    draw is postponed and entries + pot roll over to the next draw.
]]

Jackpot = {}

-- Unix time of the next draw (for the admin panel), or nil.
function Jackpot.nextDrawAt()
    local j, st = Economy.settings.jackpot, Economy.state
    if not j.drawEnabled then return nil end
    if j.drawMode == 'interval' then
        return st.lastDraw + math.floor(j.intervalHours * 3600)
    end
    local now = os.time()
    local best
    for dayOffset = 0, 1 do
        local d = os.date('*t', now + dayOffset * 86400)
        for _, hm in ipairs(j.schedule) do
            local h, m = hm:match('(%d+):(%d+)')
            local t = os.time({ year = d.year, month = d.month, day = d.day, hour = tonumber(h), min = tonumber(m), sec = 0 })
            if t > now and (not best or t < best) then best = t end
        end
    end
    return best
end

local function isDue()
    local j, st = Economy.settings.jackpot, Economy.state
    if not j.drawEnabled then return false end
    if j.drawMode == 'interval' then
        return os.time() >= st.lastDraw + math.floor(j.intervalHours * 3600)
    end
    local key = os.date('%Y-%m-%d ') .. os.date('%H:%M')
    for _, hm in ipairs(j.schedule) do
        if os.date('%H:%M') == hm and st.lastScheduleKey ~= key then
            st.lastScheduleKey = key
            return true
        end
    end
    return false
end

-- Performs a draw. force = admin "Draw now" (still honours minimums unless ignoreMin).
-- Returns ok, message.
function Jackpot.draw(ignoreMin)
    local j, st = Economy.settings.jackpot, Economy.state
    local period = st.period
    local tickets, players = DB.entryStats(period)
    st.lastDraw = os.time()

    if not ignoreMin and (players < j.minPlayers or tickets < j.minTickets) then
        Economy.saveState()
        print(('[sod_lottery] draw postponed: %d entries / %d players (need %d / %d)'):format(tickets, players, j.minTickets, j.minPlayers))
        return false, L('drawSkipped')
    end
    if tickets == 0 then
        Economy.saveState()
        return false, 'No entries to draw from.'
    end

    local winner = DB.entryAt(period, math.random(0, tickets - 1))
    if not winner then return false, 'Draw failed: entry not found' end

    local amount = st.pot
    -- move to the next period and reseed BEFORE paying, so a crash can never pay twice
    st.period = period + 1
    local seed = Economy.seedValue()
    st.pot = seed
    st.seedsInjected = (st.seedsInjected or 0) + seed
    Economy.saveState()

    PayOut(winner.identifier, amount, 'draw')
    DB.logWinner({ kind = 'draw', identifier = winner.identifier, name = winner.name, plate = nil, amount = amount })
    DB.purgeEntriesBefore(st.period)
    Telegram(L('telegramDraw', winner.name, Money(amount), tickets, Money(seed)))
    print(('[sod_lottery] jackpot draw: %s wins $%s (%d entries)'):format(winner.name, Money(amount), tickets))
    return true, ('%s wins $%s'):format(winner.name, Money(amount))
end

function Jackpot.start()
    CreateThread(function()
        while true do
            Wait(30000)
            if isDue() then
                local ok, err = pcall(Jackpot.draw, false)
                if not ok then print('^1[sod_lottery] draw error: ' .. tostring(err) .. '^0') end
            end
        end
    end)
end
