--[[
    Ticket sale, settlement and anti-abuse. Server-authoritative:
      1. server takes the money (or consumes the item), splits it, rolls the outcome
      2. client receives a finished grid to scratch
      3. client reports "scratched" -> server pays whatever it already decided
    A ticket that is never claimed is settled automatically (timeout / disconnect),
    so scratching is purely cosmetic and cannot change or skip a result.
]]

local RES = GetCurrentResourceName()
Active = {}          -- [src] = ticket in hand
local lastBuy = {}   -- [src] = GetGameTimer() of last purchase
local spam = {}      -- [src] = { count, windowStart, strikes }

function Money(n)
    n = Economy.round2(n)
    local s = (n == math.floor(n)) and ('%d'):format(n) or ('%.2f'):format(n)
    local int, frac = s:match('^(%d+)(.*)$')
    if not int then return s end
    int = int:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return int .. frac
end

function Notify(src, text, kind)
    TriggerClientEvent('sod_lottery:client:notify', src, { text = text, kind = kind or 'info' })
end

function Telegram(body)
    TriggerClientEvent('sod_lottery:client:telegram', -1, {
        head = Strings.telegramHead, body = body, sign = Strings.telegramSign,
    })
end

local function dbg(...) if Config.Debug then print('[sod_lottery]', ...) end end

---------------------------------------------------------------------------
-- Rate limiting: every lottery event goes through Guard(src).
---------------------------------------------------------------------------
function Guard(src)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    local now = GetGameTimer()
    local s = spam[src]
    if not s or now - s.windowStart > Config.Security.eventWindowMs then
        s = { count = 0, windowStart = now, strikes = s and s.strikes or 0 }
        spam[src] = s
    end
    s.count = s.count + 1
    if s.count > Config.Security.maxEventsPerWindow then
        if s.count == Config.Security.maxEventsPerWindow + 1 then
            s.strikes = s.strikes + 1
            print(('^3[sod_lottery] event spam from %s (%s), strike %d^0'):format(GetPlayerName(src) or '?', src, s.strikes))
            if Config.Security.dropOnSpam and s.strikes >= 3 then
                DropPlayer(src, 'Lottery event spam')
            end
        end
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Pay or queue
---------------------------------------------------------------------------
function FindSourceByIdentifier(identifier)
    for _, p in ipairs(GetPlayers()) do
        local s = tonumber(p)
        if Bridge.getIdentifier(s) == identifier then return s end
    end
    return nil
end

-- Pays `amount` to the character `identifier`; queues it if they are offline
-- or the framework refuses. Returns true when paid immediately.
function PayOut(identifier, amount, reason, src)
    if amount <= 0 then return true end
    src = src or FindSourceByIdentifier(identifier)
    if src and Bridge.getIdentifier(src) == identifier and Bridge.addCash(src, amount) then
        return true
    end
    DB.addPending(identifier, amount, reason)
    return false
end

local function deliverPending(src)
    local id = Bridge.getIdentifier(src)
    if not id then return end
    local total = DB.takePending(id)
    if total > 0 then
        if Bridge.addCash(src, total) then
            Notify(src, L('pendingPaid', Money(total)), 'win')
        else
            DB.addPending(id, total, 'requeue')
        end
    end
end

---------------------------------------------------------------------------
-- Selling a ticket
---------------------------------------------------------------------------
local function prizeSchedule()
    local out = {}
    for _, t in ipairs(Economy.settings.tiers) do
        if t.weight > 0 then
            out[#out + 1] = {
                plate = t.plate, label = Plates[t.plate].label, jackpot = Plates[t.plate].jackpot,
                progressive = t.type == 'progressive',
                payout = t.type ~= 'progressive' and Economy.fixedPayout(t) or 0,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.progressive ~= b.progressive then return not a.progressive end
        return a.payout < b.payout
    end)
    return out
end

-- sourceType: 'direct' (server takes cash) | 'item' (store already took cash)
-- Returns true if a ticket was issued (so an item should be consumed).
function IssueTicket(src, sourceType)
    local s, st = Economy.settings, Economy.state
    if not s.salesEnabled then Notify(src, L('salesClosed'), 'error') return false end
    if Active[src] then Notify(src, L('activeTicket'), 'error') TriggerClientEvent('sod_lottery:client:reopen', src) return false end
    local now = GetGameTimer()
    if lastBuy[src] and now - lastBuy[src] < Config.Security.purchaseCooldownMs then
        Notify(src, L('cooldown'), 'error') return false
    end
    local identifier = Bridge.getIdentifier(src)
    if not identifier then return false end
    lastBuy[src] = now
    Active[src] = { pending = true } -- reserve slot: blocks double-buys while we await the DB

    local price = s.ticketPrice
    if sourceType == 'direct' then
        if not Bridge.removeCash(src, price) then
            Active[src] = nil
            Notify(src, L('noMoney', Money(price)), 'error')
            return false
        end
    end

    -- Roll on the server first: the split depends on win/loss (loss contribution).
    local tier = Economy.roll()

    -- Split of the price (booked price = 0 for store tickets when not counted).
    -- jackpotPercent feeds the pot from EVERY ticket; lossContributionPct feeds
    -- it from LOSING tickets only (wins, including half-back, add nothing).
    local booked = (sourceType == 'direct' or Config.Item.storeSoldCountsAsRevenue) and price or 0
    local jpPct = s.jackpotPercent + (tier and 0 or s.jackpot.lossContributionPct)
    local jp = Economy.round2(math.min(booked, booked * jpPct / 100))
    local house = Economy.round2(math.min(booked * s.houseEdge / 100, booked - jp))
    if s.jackpot.maxPot > 0 and st.pot + jp > s.jackpot.maxPot then
        local room = math.max(0, s.jackpot.maxPot - st.pot)
        house = house + (jp - room)   -- overflow past the cap is retained by the house
        jp = room
    end
    local backing = Economy.round2(booked - house - jp)
    st.pot = Economy.round2(st.pot + jp)

    local payout, kind = 0, nil
    if tier then
        if tier.type == 'progressive' then
            payout = st.pot
            kind = 'jackpot'
            local seed = Economy.seedValue()
            st.pot = seed                    -- reseed immediately so nobody else can win the same pot
            st.seedsInjected = (st.seedsInjected or 0) + seed
        else
            payout = Economy.fixedPayout(tier)
            kind = (tier.plate == 'MOONSHINE' or Plates[tier.plate].jackpot) and 'moonshine' or 'instant'
        end
    end
    Economy.saveState()

    local name = Bridge.getName(src)
    local ticketId = DB.logTicket({
        identifier = identifier, name = name, source_type = sourceType, price = booked,
        house_cut = house, jackpot_cut = jp, backing_cut = backing,
        plate = tier and tier.plate or nil, payout = payout,
    })
    DB.addEntry(st.period, identifier, name)

    local grid = Economy.buildGrid(tier and tier.plate or nil)
    Active[src] = {
        id = ticketId, identifier = identifier, name = name, issuedAt = os.time(), issuedTimer = GetGameTimer(),
        plate = tier and tier.plate or nil, payout = payout, kind = kind, grid = grid,
    }
    dbg(('ticket #%s for %s -> %s $%s'):format(ticketId, name, tostring(tier and tier.plate), payout))

    if sourceType == 'direct' then Notify(src, L('bought', Money(price)), 'info') end
    TriggerClientEvent('sod_lottery:client:openTicket', src, {
        serial = ('%06d'):format(tonumber(ticketId) or 0),
        grid = grid, prizes = prizeSchedule(), pot = st.pot, price = price,
        strings = Strings.ui, loseSound = s.loseSound, legend = Economy.legend(),
    })
    return true
end

-- Settle the ticket in hand. Safe to call more than once.
function SettleTicket(src, reason)
    local t = Active[src]
    if not t or t.pending or t.settled then return nil end
    t.settled = true
    Active[src] = nil

    local paidNow = true
    if t.payout > 0 then
        if reason == 'dropped' then
            DB.addPending(t.identifier, t.payout, 'ticket')
            paidNow = false
        else
            paidNow = PayOut(t.identifier, t.payout, 'ticket', src)
        end
        DB.logWinner({ kind = t.kind, identifier = t.identifier, name = t.name, plate = t.plate, amount = t.payout })
        if t.kind == 'jackpot' then
            Telegram(L('telegramJackpotInstant', t.name, Money(t.payout), Money(Economy.seedValue())))
        elseif t.kind == 'moonshine' then
            Telegram(L('telegramMoonshine', t.name, Money(t.payout)))
        end
    end
    return {
        win = t.payout > 0, plate = t.plate, label = t.plate and Plates[t.plate].label or nil,
        payout = t.payout, kind = t.kind or 'loss', paidNow = paidNow, pot = Economy.state.pot,
    }
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
RegisterNetEvent('sod_lottery:server:claim', function(serial)
    local src = source
    if not Guard(src) then return end
    local t = Active[src]
    if not t or t.pending then return end
    if ('%06d'):format(tonumber(t.id) or 0) ~= tostring(serial) then return end -- stale / forged
    local result = SettleTicket(src, 'claimed')
    if not result then return end
    if result.win then
        local text = result.kind == 'jackpot' and L('jackpotWon', Money(result.payout))
            or L('won', result.label, Money(result.payout))
        Notify(src, text, 'win')
    else
        Notify(src, L('lost'), 'info')
    end
    TriggerClientEvent('sod_lottery:client:claimResult', src, result)
end)

RegisterNetEvent('sod_lottery:server:buy', function()
    local src = source
    if not Guard(src) then return end
    if not Config.DirectSale.enabled then return end
    IssueTicket(src, 'direct')
end)

RegisterNetEvent('sod_lottery:server:reopen', function()
    local src = source
    if not Guard(src) then return end
    local t = Active[src]
    if not t or t.pending then return end
    TriggerClientEvent('sod_lottery:client:openTicket', src, {
        serial = ('%06d'):format(tonumber(t.id) or 0), grid = t.grid, prizes = prizeSchedule(),
        pot = Economy.state.pot, price = Economy.settings.ticketPrice, strings = Strings.ui,
        loseSound = Economy.settings.loseSound, legend = Economy.legend(),
    })
end)

RegisterNetEvent('sod_lottery:server:ready', function()
    local src = source
    if not Guard(src) then return end
    deliverPending(src)
    TriggerClientEvent('sod_lottery:client:config', src, {
        price = Economy.settings.ticketPrice, salesEnabled = Economy.settings.salesEnabled,
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Active[src] and not Active[src].pending then SettleTicket(src, 'dropped') end
    Active[src] = nil
    lastBuy[src] = nil
    spam[src] = nil
end)

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------
CreateThread(function()
    math.randomseed(os.time() ~ (GetGameTimer() << 16))
    DB.init()
    Bridge.init()
    Economy.load()

    Bridge.registerUsableItem(Config.Item.name, function(src)
        if not Guard(src) then return false end
        return IssueTicket(src, 'item')
    end)
    Bridge.onCharacterLoaded(function(src) SetTimeout(5000, function() deliverPending(src) end) end)

    if Config.DirectSale.enabled and Config.DirectSale.command then
        RegisterCommand(Config.DirectSale.command, function(src)
            if src <= 0 or not Guard(src) then return end
            IssueTicket(src, 'direct')
        end, false)
    end

    if Jackpot and Jackpot.start then Jackpot.start() end
    print(('[sod_lottery] %s ready - ticket $%s, pot $%s, persistence: %s'):format(
        Strings.lotteryName, Money(Economy.settings.ticketPrice), Money(Economy.state.pot), DB.online and 'oxmysql' or 'memory'))

    -- auto-settle abandoned tickets
    while true do
        Wait(10000)
        local now = os.time()
        for src, t in pairs(Active) do
            if not t.pending and now - t.issuedAt > Config.Security.ticketTimeoutSec then
                local r = SettleTicket(src, 'timeout')
                if r then TriggerClientEvent('sod_lottery:client:claimResult', src, r) end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= RES then return end
    -- Pay tickets still in hand so a restart never eats a prize. Database calls
    -- are not reliable while stopping, so only the (synchronous) framework call is used;
    -- the ticket and its payout are already in sod_lottery_tickets for auditing.
    for src, t in pairs(Active) do
        if not t.pending and not t.settled and t.payout > 0 then
            pcall(Bridge.addCash, src, t.payout)
        end
    end
    Active = {}
end)
