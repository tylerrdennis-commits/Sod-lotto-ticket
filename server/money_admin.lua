--[[
    Admin money commands: /givemoney [playerId] [amount] and /takemoney [playerId] [amount]
    (names configurable in Config.AdminMoney). Permission: ACE `sod_lottery.admin`
    or the server console. All money moves go through server/bridge.lua.
    Every use is printed to the console and stored in `sod_lottery_audit`.
]]

local AM = Config.AdminMoney
if not (AM and AM.enabled) then return end

local function reply(src, msg, kind)
    if src == 0 then print('[sod_lottery] ' .. msg) else Notify(src, msg, kind) end
end

local function adminLabel(src)
    if src == 0 then return 'console' end
    return ('%s (id %d, %s)'):format(GetPlayerName(src) or '?', src, Bridge.getIdentifier(src) or 'no-char')
end

-- Parses and validates arguments. Returns target, amount or nil, error.
local function parse(args)
    local target, amount = tonumber(args[1]), tonumber(args[2])
    if not target or not amount then return nil, 'Usage: /%s [playerId] [amount]' end
    target = math.floor(target)
    if not GetPlayerName(target) then return nil, ('Player %d is not online.'):format(target) end
    if not Bridge.getIdentifier(target) then return nil, ('Player %d has no character loaded.'):format(target) end
    if amount ~= amount or amount <= 0 or amount == math.huge then return nil, 'Amount must be a positive number.' end
    local cents = amount * 100
    if math.abs(cents - math.floor(cents + 0.5)) > 1e-6 then return nil, 'Amount may have at most 2 decimals.' end
    amount = math.floor(cents + 0.5) / 100
    if amount > AM.maxAmount then return nil, ('Amount exceeds the limit of $%s per command.'):format(Money(AM.maxAmount)) end
    return target, amount
end

local function allowed(src)
    if src == 0 then return true end
    if not Guard(src) then return false end
    local ok = IsPlayerAceAllowed(tostring(src), Config.Admin.ace)
    return ok == true or ok == 1
end

local function audit(action, src, target, amount, before, after)
    local entry = {
        action = action, admin = adminLabel(src),
        target = ('%s (id %d, %s)'):format(Bridge.getName(target), target, Bridge.getIdentifier(target) or '?'),
        amount = amount, before = before, after = after,
    }
    print(('[sod_lottery][audit] %s by %s -> %s: $%s (cash $%s -> $%s)'):format(
        action, entry.admin, entry.target, Money(amount), Money(before), Money(after)))
    DB.logAudit(entry)
end

local function handler(action)
    return function(src, args)
        if not allowed(src) then
            if src > 0 then Notify(src, L('notAdmin'), 'error') end
            return
        end
        local target, amount = parse(args)
        if not target then reply(src, (amount):format(action == 'givemoney' and AM.giveCommand or AM.takeCommand), 'error') return end

        local before = Bridge.getCash(target)
        local ok
        if action == 'givemoney' then
            ok = Bridge.addCash(target, amount)
        else
            if before < amount then
                if AM.takeMode == 'partial' and before > 0 then
                    amount = math.floor(before * 100) / 100
                else
                    reply(src, ('%s only has $%s; nothing taken.'):format(Bridge.getName(target), Money(before)), 'error')
                    return
                end
            end
            ok = Bridge.removeCash(target, amount)
        end
        if not ok then reply(src, 'The framework refused the transaction.', 'error') return end

        local after = Bridge.getCash(target)
        audit(action, src, target, amount, before, after)
        local name = Bridge.getName(target)
        if action == 'givemoney' then
            reply(src, ('Gave $%s to %s (id %d).'):format(Money(amount), name, target), 'info')
            Notify(target, ('The Territorial Commission has paid you $%s.'):format(Money(amount)), 'win')
        else
            reply(src, ('Took $%s from %s (id %d).'):format(Money(amount), name, target), 'info')
            Notify(target, ('The Territorial Commission has collected $%s from you.'):format(Money(amount)), 'error')
        end
    end
end

RegisterCommand(AM.giveCommand, handler('givemoney'), false)
RegisterCommand(AM.takeCommand, handler('takemoney'), false)
