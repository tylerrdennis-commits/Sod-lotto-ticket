--[[
    Framework bridge. Everything framework-specific lives in this file:
      Bridge.name                      -> 'vorp' | 'rsg' | 'standalone'
      Bridge.getIdentifier(src)        -> stable per-CHARACTER id string (or nil if not loaded)
      Bridge.getName(src)              -> in-character display name
      Bridge.getCash(src)              -> number
      Bridge.removeCash(src, amount)   -> bool
      Bridge.addCash(src, amount)      -> bool
      Bridge.isAdmin(src)              -> bool (framework group OR ACE)
      Bridge.registerUsableItem(name, cb(src))  cb returns true if the item should be consumed
      Bridge.removeItem(src, name, count, ctx)  -> bool
      Bridge.onCharacterLoaded(cb(src))
]]

Bridge = { name = 'standalone' }

-- CASH ON HAND ONLY (hard-coded, not configurable): every purchase, prize and
-- admin money command uses cash. Bank and gold are never touched.
local VORP_CASH = 0       -- VORP currency type 0 = cash (1 = gold, 2 = rol)
local RSG_CASH = 'cash'   -- RSG money type; never 'bank'

local function detect()
    local fw = Config.Framework
    if fw ~= 'auto' then return fw end
    if GetResourceState('vorp_core') == 'started' then return 'vorp' end
    if GetResourceState('rsg-core') == 'started' then return 'rsg' end
    return 'standalone'
end

local function aceAdmin(src)
    local ok = IsPlayerAceAllowed(tostring(src), Config.Admin.ace)
    return ok == true or ok == 1
end

local function round2(n) return math.floor(n * 100 + 0.5) / 100 end

---------------------------------------------------------------------------
-- VORP Core
---------------------------------------------------------------------------
local function setupVorp()
    local Core = exports.vorp_core:GetCore()

    local function char(src)
        local user = Core.getUser(src)
        if not user then return nil, nil end
        return user.getUsedCharacter, user
    end

    Bridge.getIdentifier = function(src)
        local c = char(src)
        if not c or not c.charIdentifier then return nil end
        return 'vorp:' .. tostring(c.charIdentifier)
    end
    Bridge.getName = function(src)
        local c = char(src)
        if not c then return GetPlayerName(src) or 'A stranger' end
        return (((c.firstname or '') .. ' ' .. (c.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''))
    end
    Bridge.getCash = function(src)  -- Character.money = cash on hand
        local c = char(src)
        return c and tonumber(c.money) or 0
    end
    Bridge.removeCash = function(src, amount)
        local c = char(src)
        if not c or (tonumber(c.money) or 0) < amount then return false end
        c.removeCurrency(VORP_CASH, round2(amount))
        return true
    end
    Bridge.addCash = function(src, amount)
        local c = char(src)
        if not c then return false end
        c.addCurrency(VORP_CASH, round2(amount))
        return true
    end
    Bridge.isAdmin = function(src)
        if aceAdmin(src) then return true end
        local c, user = char(src)
        local groups = {}
        if user and user.getGroup then groups[#groups + 1] = user.getGroup end
        if c and c.group then groups[#groups + 1] = c.group end
        for _, g in ipairs(groups) do
            for _, allowed in ipairs(Config.Admin.vorpGroups) do
                if g == allowed then return true end
            end
        end
        return false
    end
    Bridge.registerUsableItem = function(name, cb)
        exports.vorp_inventory:registerUsableItem(name, function(data)
            local src = data.source
            if cb(src) then
                exports.vorp_inventory:subItem(src, name, 1)
            end
            exports.vorp_inventory:closeInventory(src)
        end)
    end
    Bridge.onCharacterLoaded = function(cb)
        AddEventHandler('vorp:SelectedCharacter', function(src) cb(src) end)
    end
end

---------------------------------------------------------------------------
-- RSG Core
---------------------------------------------------------------------------
local function setupRsg()
    local Core = exports['rsg-core']:GetCoreObject()
    local function player(src) return Core.Functions.GetPlayer(src) end

    Bridge.getIdentifier = function(src)
        local p = player(src)
        return p and ('rsg:' .. p.PlayerData.citizenid) or nil
    end
    Bridge.getName = function(src)
        local p = player(src)
        if not p then return GetPlayerName(src) or 'A stranger' end
        local ci = p.PlayerData.charinfo or {}
        return (((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''))
    end
    Bridge.getCash = function(src)
        local p = player(src)
        return p and tonumber(p.PlayerData.money and p.PlayerData.money[RSG_CASH]) or 0
    end
    Bridge.removeCash = function(src, amount)
        local p = player(src)
        if not p or Bridge.getCash(src) < amount then return false end
        return p.Functions.RemoveMoney(RSG_CASH, round2(amount), 'sod-lottery') ~= false
    end
    Bridge.addCash = function(src, amount)
        local p = player(src)
        if not p then return false end
        return p.Functions.AddMoney(RSG_CASH, round2(amount), 'sod-lottery') ~= false
    end
    Bridge.isAdmin = function(src)
        if aceAdmin(src) then return true end
        for _, perm in ipairs(Config.Admin.rsgPermissions) do
            if Core.Functions.HasPermission(src, perm) then return true end
        end
        return false
    end
    Bridge.registerUsableItem = function(name, cb)
        Core.Functions.CreateUseableItem(name, function(src, item)
            if cb(src) then
                local p = player(src)
                if p and p.Functions.RemoveItem(name, 1, item and item.slot) then
                    local shared = Core.Shared and Core.Shared.Items and Core.Shared.Items[name]
                    if shared then TriggerClientEvent('rsg-inventory:client:ItemBox', src, shared, 'remove', 1) end
                end
            end
        end)
    end
    Bridge.onCharacterLoaded = function(cb)
        AddEventHandler('RSGCore:Server:PlayerLoaded', function(p)
            if p and p.PlayerData then cb(p.PlayerData.source) end
        end)
    end
end

---------------------------------------------------------------------------
-- Standalone fallback (testing / custom frameworks).
-- Cash is kept in memory only. Replace these with your own economy calls.
---------------------------------------------------------------------------
local function setupStandalone()
    local wallets = {}
    local function license(src)
        for _, id in ipairs(GetPlayerIdentifiers(src)) do
            if id:sub(1, 8) == 'license:' then return id end
        end
        return 'src:' .. tostring(src)
    end
    Bridge.getIdentifier = function(src) return 'sa:' .. license(src) end
    Bridge.getName = function(src) return GetPlayerName(src) or 'A stranger' end
    Bridge.getCash = function(src) return wallets[license(src)] or 100 end
    Bridge.removeCash = function(src, amount)
        local cash = Bridge.getCash(src)
        if cash < amount then return false end
        wallets[license(src)] = round2(cash - amount)
        return true
    end
    Bridge.addCash = function(src, amount)
        wallets[license(src)] = round2(Bridge.getCash(src) + amount)
        return true
    end
    Bridge.isAdmin = function(src) return aceAdmin(src) end
    Bridge.registerUsableItem = function() end -- no inventory; use /buyticket
    Bridge.onCharacterLoaded = function() end  -- client 'ready' event covers this
end

function Bridge.init()
    Bridge.name = detect()
    if Bridge.name == 'vorp' then setupVorp()
    elseif Bridge.name == 'rsg' then setupRsg()
    else Bridge.name = 'standalone'; setupStandalone() end
    print(('[sod_lottery] framework bridge: %s'):format(Bridge.name))
end
