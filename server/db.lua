--[[
    Thin persistence layer over oxmysql exports (no @oxmysql/lib include, so the
    resource still starts without oxmysql). Without oxmysql everything runs in
    memory and is lost on restart - a warning is printed.
    All functions here are synchronous and must be called from a thread/handler.
]]

DB = { online = false }

local mem = { kv = {}, tickets = {}, entries = {}, winners = {}, pending = {}, nextId = 1 }

local function await(fn, ...)
    local p = promise.new()
    local args = { ... }
    args[#args + 1] = function(result) p:resolve(result) end
    fn(table.unpack(args))
    return Citizen.Await(p)
end

local function q(sql, params)   return await(function(...) exports.oxmysql:query(...) end, sql, params or {}) end
local function ins(sql, params) return await(function(...) exports.oxmysql:insert(...) end, sql, params or {}) end

local function nowTs() return os.time() end

function DB.init()
    DB.online = GetResourceState('oxmysql') == 'started'
    if not DB.online then
        print('^3[sod_lottery] oxmysql is not started - running IN MEMORY. Nothing will persist across restarts.^0')
        return
    end
    if Config.AutoCreateTables then
        local file = LoadResourceFile(GetCurrentResourceName(), 'sql/install.sql')
        if file then
            -- strip comments, split on ';'
            file = file:gsub('%-%-[^\n]*', '')
            for stmt in file:gmatch('([^;]+);') do
                if stmt:match('%S') then q(stmt) end
            end
        end
    end
end

-- Key/value JSON store --------------------------------------------------------
function DB.getKV(k)
    if not DB.online then return mem.kv[k] end
    local rows = q('SELECT v FROM sod_lottery_kv WHERE k = ?', { k })
    if rows and rows[1] then return json.decode(rows[1].v) end
    return nil
end

function DB.setKV(k, v)
    if not DB.online then mem.kv[k] = v return end
    q('INSERT INTO sod_lottery_kv (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', { k, json.encode(v) })
end

function DB.deleteKV(k)
    if not DB.online then mem.kv[k] = nil return end
    q('DELETE FROM sod_lottery_kv WHERE k = ?', { k })
end

-- Tickets ---------------------------------------------------------------------
function DB.logTicket(t)
    if not DB.online then
        t.id = mem.nextId; mem.nextId = mem.nextId + 1; t.created_at = nowTs()
        mem.tickets[#mem.tickets + 1] = t
        return t.id
    end
    return ins([[INSERT INTO sod_lottery_tickets
        (identifier, name, source_type, price, house_cut, jackpot_cut, backing_cut, plate, payout)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { t.identifier, t.name, t.source_type, t.price, t.house_cut, t.jackpot_cut, t.backing_cut, t.plate, t.payout })
end

function DB.ledgerTotals()
    if not DB.online then
        local r = { sold = 0, money_in = 0, house = 0, jackpot_fed = 0, backing = 0, instant_paid = 0 }
        for _, t in ipairs(mem.tickets) do
            r.sold = r.sold + 1; r.money_in = r.money_in + t.price; r.house = r.house + t.house_cut
            r.jackpot_fed = r.jackpot_fed + t.jackpot_cut; r.backing = r.backing + t.backing_cut
            if t.plate ~= 'OIL_PUMP' then r.instant_paid = r.instant_paid + t.payout end
        end
        return r
    end
    local rows = q([[SELECT COUNT(*) AS sold, COALESCE(SUM(price),0) AS money_in, COALESCE(SUM(house_cut),0) AS house,
        COALESCE(SUM(jackpot_cut),0) AS jackpot_fed, COALESCE(SUM(backing_cut),0) AS backing,
        COALESCE(SUM(CASE WHEN plate <> 'OIL_PUMP' OR plate IS NULL THEN payout ELSE 0 END),0) AS instant_paid
        FROM sod_lottery_tickets]])
    local r = rows and rows[1] or {}
    for k, v in pairs(r) do r[k] = tonumber(v) or 0 end
    return r
end

-- Winners ---------------------------------------------------------------------
function DB.logWinner(w)
    if not DB.online then
        w.created_at = nowTs(); mem.winners[#mem.winners + 1] = w -- appended; read newest-first
        return
    end
    ins('INSERT INTO sod_lottery_winners (kind, identifier, name, plate, amount) VALUES (?, ?, ?, ?, ?)',
        { w.kind, w.identifier, w.name, w.plate, w.amount })
end

function DB.recentWinners(limit)
    if not DB.online then
        local out = {}
        for i = 1, math.min(limit, #mem.winners) do
            local w = mem.winners[#mem.winners - i + 1]
            out[i] = { kind = w.kind, name = w.name, plate = w.plate, amount = w.amount, created_at = os.date('%Y-%m-%d %H:%M', w.created_at) }
        end
        return out
    end
    local rows = q([[SELECT kind, name, plate, amount, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS created_at
        FROM sod_lottery_winners ORDER BY id DESC LIMIT ?]], { limit }) or {}
    for _, r in ipairs(rows) do r.amount = tonumber(r.amount) or 0 end
    return rows
end

function DB.jackpotPaidTotal()
    if not DB.online then
        local s = 0
        for _, w in ipairs(mem.winners) do if w.kind == 'jackpot' or w.kind == 'draw' then s = s + w.amount end end
        return s
    end
    local rows = q("SELECT COALESCE(SUM(amount),0) AS s FROM sod_lottery_winners WHERE kind IN ('jackpot','draw')")
    return tonumber(rows and rows[1] and rows[1].s) or 0
end

-- Draw entries ----------------------------------------------------------------
function DB.addEntry(period, identifier, name)
    if not DB.online then
        mem.entries[#mem.entries + 1] = { period = period, identifier = identifier, name = name }
        return
    end
    ins('INSERT INTO sod_lottery_entries (period, identifier, name) VALUES (?, ?, ?)', { period, identifier, name })
end

function DB.entryStats(period)
    if not DB.online then
        local total, seen, players = 0, {}, 0
        for _, e in ipairs(mem.entries) do
            if e.period == period then
                total = total + 1
                if not seen[e.identifier] then seen[e.identifier] = true; players = players + 1 end
            end
        end
        return total, players
    end
    local rows = q('SELECT COUNT(*) AS t, COUNT(DISTINCT identifier) AS p FROM sod_lottery_entries WHERE period = ?', { period })
    local r = rows and rows[1] or {}
    return tonumber(r.t) or 0, tonumber(r.p) or 0
end

-- Pick the n-th entry (0-based) of a period; offset chosen with server RNG.
function DB.entryAt(period, offset)
    if not DB.online then
        local i = 0
        for _, e in ipairs(mem.entries) do
            if e.period == period then
                if i == offset then return e end
                i = i + 1
            end
        end
        return nil
    end
    local rows = q('SELECT identifier, name FROM sod_lottery_entries WHERE period = ? ORDER BY id LIMIT 1 OFFSET ?', { period, offset })
    return rows and rows[1]
end

function DB.purgeEntriesBefore(period)
    if not DB.online then
        local keep = {}
        for _, e in ipairs(mem.entries) do if e.period >= period then keep[#keep + 1] = e end end
        mem.entries = keep
        return
    end
    q('DELETE FROM sod_lottery_entries WHERE period < ?', { period })
end

-- Audit log (admin money commands) -------------------------------------------
function DB.logAudit(a)
    if not DB.online then return end -- console log only when running in memory
    ins('INSERT INTO sod_lottery_audit (action, admin, target, amount, before_cash, after_cash) VALUES (?, ?, ?, ?, ?, ?)',
        { a.action, a.admin, a.target, a.amount, a.before, a.after })
end

-- Pending payouts (winners who were offline) -------------------------------
function DB.addPending(identifier, amount, reason)
    if not DB.online then
        mem.pending[#mem.pending + 1] = { identifier = identifier, amount = amount, reason = reason }
        return
    end
    ins('INSERT INTO sod_lottery_pending (identifier, amount, reason) VALUES (?, ?, ?)', { identifier, amount, reason })
end

-- Atomically takes (returns and deletes) all pending payouts for an identifier.
function DB.takePending(identifier)
    if not DB.online then
        local total, keep = 0, {}
        for _, p in ipairs(mem.pending) do
            if p.identifier == identifier then total = total + p.amount else keep[#keep + 1] = p end
        end
        mem.pending = keep
        return total
    end
    local rows = q('SELECT id, amount FROM sod_lottery_pending WHERE identifier = ?', { identifier }) or {}
    local total = 0
    for _, r in ipairs(rows) do
        -- delete row-by-row and only count rows we actually deleted (guards double-pay races)
        local res = q('DELETE FROM sod_lottery_pending WHERE id = ?', { r.id })
        local affected = type(res) == 'table' and (res.affectedRows or 0) or (tonumber(res) or 0)
        if affected > 0 then total = total + (tonumber(r.amount) or 0) end
    end
    return total
end
