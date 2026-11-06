--[[
    Economy: settings (load / validate / persist), RTP maths, the server-side
    outcome roll and the 3x3 grid generator. The client never decides anything;
    it only receives the finished grid to draw under the foil.
]]

Economy = { settings = nil, state = nil }

local function deepcopy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = deepcopy(v) end
    return o
end
Economy.deepcopy = deepcopy

local function round2(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end
Economy.round2 = round2

---------------------------------------------------------------------------
-- Validation. Returns cleaned settings or nil, errorMessage.
-- Applied to every admin save; also to DB-loaded settings on start.
---------------------------------------------------------------------------
local function num(v, name, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil, name .. ' must be a number' end
    if v < lo or v > hi then return nil, ('%s must be between %s and %s'):format(name, lo, hi) end
    return v
end

function Economy.validate(input)
    if type(input) ~= 'table' then return nil, 'no data' end
    local Lm, out, err = Config.Limits, {}, nil

    out.salesEnabled = input.salesEnabled == true
    out.loseSound = (input.loseSound == 'fart') and 'fart' or 'sadtrombone'
    out.autoScalePayouts = input.autoScalePayouts == true
    out.rtpJackpotBasis = (input.rtpJackpotBasis == 'seed') and 'seed' or 'current'

    out.ticketPrice, err = num(input.ticketPrice, 'Ticket price', Lm.priceMin, Lm.priceMax); if err then return nil, err end
    out.ticketPrice = round2(out.ticketPrice)
    out.printRun, err = num(input.printRun, 'Print run', Lm.printRunMin, Lm.printRunMax); if err then return nil, err end
    out.printRun = math.floor(out.printRun)
    out.houseEdge, err = num(input.houseEdge, 'House edge %', 0, 100); if err then return nil, err end
    out.jackpotPercent, err = num(input.jackpotPercent, 'Jackpot %', 0, 100); if err then return nil, err end
    if out.houseEdge + out.jackpotPercent > 100 then return nil, 'House edge % + jackpot % cannot exceed 100' end

    -- tiers
    if type(input.tiers) ~= 'table' or #input.tiers == 0 then return nil, 'At least one prize tier is required' end
    if #input.tiers > Lm.maxTiers then return nil, 'Too many tiers (max ' .. Lm.maxTiers .. ')' end
    out.tiers = {}
    local seen, weightSum, progressiveCount = {}, 0, 0
    for i, t in ipairs(input.tiers) do
        if type(t) ~= 'table' then return nil, 'Tier ' .. i .. ' is malformed' end
        local plate = tostring(t.plate or '')
        if not Plates[plate] or plate == 'FILLER' then return nil, 'Tier ' .. i .. ': unknown symbol' end
        if seen[plate] then return nil, 'Symbol ' .. Plates[plate].label .. ' is used by two tiers' end
        seen[plate] = true
        local ttype = (t.type == 'progressive' or t.type == 'price_ratio') and t.type or 'fixed'
        local payout, ratio = 0, nil
        if ttype == 'price_ratio' then
            ratio, err = num(t.ratio, 'Tier ' .. i .. ' ratio', Lm.ratioMin, Lm.ratioMax); if err then return nil, err end
            ratio = math.floor(ratio * 1000 + 0.5) / 1000
        elseif ttype == 'fixed' then
            payout, err = num(t.payout, 'Tier ' .. i .. ' payout', 0.01, Lm.payoutMax); if err then return nil, err end
            payout = round2(payout)
        else
            progressiveCount = progressiveCount + 1
        end
        local weight
        weight, err = num(t.weight, 'Tier ' .. i .. ' weight', 0, out.printRun); if err then return nil, err end
        weight = math.floor(weight)
        weightSum = weightSum + weight
        out.tiers[#out.tiers + 1] = { plate = plate, type = ttype, payout = payout, ratio = ratio, weight = weight }
    end
    if progressiveCount > 1 then return nil, 'Only one tier may pay the progressive jackpot' end
    if weightSum > out.printRun then return nil, 'Sum of tier weights exceeds the print run' end

    -- jackpot
    local j = type(input.jackpot) == 'table' and input.jackpot or {}
    out.jackpot = {}
    out.jackpot.seed, err = num(j.seed, 'Jackpot seed', 0, Lm.seedMax); if err then return nil, err end
    out.jackpot.seed = round2(out.jackpot.seed)
    out.jackpot.maxPot, err = num(j.maxPot or 0, 'Jackpot cap', 0, Lm.payoutMax * 100); if err then return nil, err end
    out.jackpot.lossContributionPct, err = num(j.lossContributionPct or 0, 'Loss-to-jackpot %', 0, 100); if err then return nil, err end
    out.jackpot.lossContributionPct = math.floor(out.jackpot.lossContributionPct + 0.5)
    out.jackpot.drawEnabled = j.drawEnabled == true
    out.jackpot.drawMode = (j.drawMode == 'schedule') and 'schedule' or 'interval'
    out.jackpot.intervalHours, err = num(j.intervalHours, 'Draw interval (hours)', Lm.intervalHoursMin, Lm.intervalHoursMax); if err then return nil, err end
    out.jackpot.minPlayers, err = num(j.minPlayers, 'Minimum players', 1, 1000); if err then return nil, err end
    out.jackpot.minTickets, err = num(j.minTickets, 'Minimum tickets', 1, 1000000); if err then return nil, err end
    out.jackpot.minPlayers = math.floor(out.jackpot.minPlayers)
    out.jackpot.minTickets = math.floor(out.jackpot.minTickets)
    out.jackpot.schedule = {}
    local sched = j.schedule
    if type(sched) == 'string' then
        local list = {}
        for part in sched:gmatch('[^,%s]+') do list[#list + 1] = part end
        sched = list
    end
    if type(sched) == 'table' then
        for _, s in ipairs(sched) do
            local h, m = tostring(s):match('^(%d%d?):(%d%d)$')
            h, m = tonumber(h), tonumber(m)
            if not h or h > 23 or m > 59 then return nil, 'Schedule times must look like 20:00' end
            out.jackpot.schedule[#out.jackpot.schedule + 1] = ('%02d:%02d'):format(h, m)
            if #out.jackpot.schedule >= 24 then break end
        end
    end
    if out.jackpot.drawMode == 'schedule' and #out.jackpot.schedule == 0 then
        return nil, 'Schedule mode needs at least one time'
    end
    return out
end

---------------------------------------------------------------------------
-- RTP maths
---------------------------------------------------------------------------
-- Returns a table describing the economics of a settings table. `pot` is the
-- current progressive pot. Used by the server (auto-scale) and mirrored
-- in html/app.js for the live admin preview.
-- Price factor: fixed payouts and the seed are written for Config.basePrice.
function Economy.priceFactor(s)
    s = s or Economy.settings
    return s.ticketPrice / (Config.basePrice or s.ticketPrice)
end

-- Jackpot seed at the current ticket price (seed x price / basePrice), in cents.
function Economy.seedValue(s)
    s = s or Economy.settings
    return round2(s.jackpot.seed * Economy.priceFactor(s))
end

function Economy.analyse(s, pot)
    local price, run = s.ticketPrice, s.printRun
    local f = Economy.priceFactor(s)
    local seed = s.jackpot.seed * f
    local fixedEV, ratioEV, winWeight, progWeight = 0, 0, 0, 0
    for _, t in ipairs(s.tiers) do
        winWeight = winWeight + t.weight
        if t.type == 'fixed' then fixedEV = fixedEV + t.payout * f * t.weight / run
        elseif t.type == 'price_ratio' then ratioEV = ratioEV + t.ratio * price * t.weight / run
        else progWeight = progWeight + t.weight end
    end
    local losePct = (run - winWeight) / run * 100
    -- average % of each ticket fed to the pot (every-ticket % + losing tickets' %)
    local potFeedPct = s.jackpotPercent + losePct / 100 * (s.jackpot.lossContributionPct or 0)
    -- seed money re-injected after each Oil Pump hit, as % of price (draw reseeds excluded)
    local seedPct = progWeight / run * seed / price * 100
    local backingPct = 100 - s.houseEdge - potFeedPct - seedPct
    -- auto-scale only touches 'fixed' tiers; they fill whatever backing the ratio tiers leave
    local targetFixedEV = math.max(0, price * backingPct / 100 - ratioEV)
    local scale = 1
    if s.autoScalePayouts and fixedEV > 0 then scale = targetFixedEV / fixedEV end
    local scaledFixedEV = fixedEV * scale + ratioEV

    local basis = (s.rtpJackpotBasis == 'seed') and seed or math.max(pot or 0, seed)
    local progEV = progWeight / run * basis

    local rtpFixed = scaledFixedEV / price * 100
    local rtpProg  = progEV / price * 100
    local rtpTotal = rtpFixed + rtpProg
    -- long-run: every dollar fed to the pot is eventually paid back out, plus the
    -- seed money re-injected after each Oil Pump hit (periodic-draw reseeds excluded)
    local rtpLongRun = rtpFixed + potFeedPct + seedPct
    return {
        backingPct = backingPct, potFeedPct = potFeedPct,
        fixedEV = scaledFixedEV, progEV = progEV, scale = scale,
        rtpFixed = rtpFixed, rtpProgressive = rtpProg, rtpTotal = rtpTotal,
        rtpLongRun = rtpLongRun,
        effectiveEdge = 100 - rtpTotal,          -- instant (pot valued at basis)
        longRunEdge = 100 - rtpLongRun,          -- after the pot is paid back
        winOdds = winWeight > 0 and run / winWeight or 0,
        winPct = winWeight / run * 100, losePct = losePct,
        edgeAchieved = rtpLongRun <= 100 - s.houseEdge + 1e-6,
        over100 = rtpTotal > 100 or rtpLongRun > 100,
    }
end

-- Odds legend for the back of the ticket, computed from the LIVE settings
-- (auto-scaled payouts included) so it stays correct after admin changes.
function Economy.legend()
    local s, st = Economy.settings, Economy.state
    local a = Economy.analyse(s, st.pot)
    local rows = {}
    for _, t in ipairs(s.tiers) do
        if t.weight > 0 then
            rows[#rows + 1] = {
                plate = t.plate, label = Plates[t.plate].label, type = t.type, ratio = t.ratio,
                payout = t.type == 'progressive' and st.pot or Economy.fixedPayout(t),
                oddsN = s.printRun / t.weight,
            }
        end
    end
    local rank = { progressive = 0, fixed = 1, price_ratio = 2 }
    -- order: progressive jackpot, fixed prizes high to low, then price-ratio (half back) last
    table.sort(rows, function(x, y)
        if rank[x.type] ~= rank[y.type] then return rank[x.type] < rank[y.type] end
        return x.payout > y.payout
    end)
    return {
        price = s.ticketPrice, basePrice = Config.basePrice, rows = rows, pot = st.pot, seed = Economy.seedValue(s),
        winPct = a.winPct, losePct = a.losePct,
        rtpInstant = a.rtpFixed, rtpLongRun = a.rtpLongRun,
        lossContributionPct = s.jackpot.lossContributionPct, jackpotPercent = s.jackpotPercent,
        autoScaled = s.autoScalePayouts and math.abs(a.scale - 1) > 1e-9,
    }
end

-- Payout actually paid for a fixed (after optional auto-scale) or price_ratio tier.
function Economy.fixedPayout(tier)
    local s = Economy.settings
    if tier.type == 'price_ratio' then return round2(s.ticketPrice * tier.ratio) end
    local a = Economy.analyse(s, Economy.state.pot)
    -- base payout x price factor, then the optional auto-scale on top
    return round2(tier.payout * Economy.priceFactor(s) * a.scale)
end

---------------------------------------------------------------------------
-- Outcome roll (server RNG) and grid
---------------------------------------------------------------------------
function Economy.roll()
    local s = Economy.settings
    local r = math.random(1, s.printRun)   -- Lua 5.4 xoshiro256**, seeded at start
    local acc = 0
    for _, t in ipairs(s.tiers) do
        acc = acc + t.weight
        if r <= acc then return t end
    end
    return nil -- loss
end

-- One row of 3 plates. Win: all three show the winning symbol. Loss: three
-- plates that never all match (mixed symbols, tumbleweed as filler; a pair
-- is allowed as a "near miss"). The roll above decides; this only draws it.
function Economy.buildGrid(winPlate)
    if winPlate then return { winPlate, winPlate, winPlate } end
    local pool = { Plates.FILLER }
    for _, id in ipairs(PlateOrder) do pool[#pool + 1] = id end
    local cells
    repeat
        cells = {}
        for i = 1, 3 do
            cells[i] = (math.random() < 0.3) and Plates.FILLER or pool[math.random(1, #pool)]
        end
    until not (cells[1] == cells[2] and cells[2] == cells[3])
    return cells
end

---------------------------------------------------------------------------
-- Load / save
---------------------------------------------------------------------------
function Economy.load()
    local stored = DB.getKV('settings')
    local cleaned
    if stored then
        local err
        cleaned, err = Economy.validate(stored)
        if not cleaned then
            print('^1[sod_lottery] stored settings invalid (' .. tostring(err) .. '), using config defaults^0')
        end
    end
    Economy.settings = cleaned or assert(Economy.validate(deepcopy(Config.Defaults)), 'Config.Defaults are invalid')

    Economy.state = DB.getKV('state') or {}
    local st = Economy.state
    st.pot = tonumber(st.pot) or Economy.seedValue()
    st.period = tonumber(st.period) or 1
    st.lastDraw = tonumber(st.lastDraw) or os.time()
    st.seedsInjected = tonumber(st.seedsInjected) or st.pot -- first seed counts as injected
    st.lastScheduleKey = st.lastScheduleKey or ''
    DB.setKV('state', st)
end

function Economy.saveSettings(s)
    Economy.settings = s
    DB.setKV('settings', s)
end

function Economy.saveState()
    DB.setKV('state', Economy.state)
end
