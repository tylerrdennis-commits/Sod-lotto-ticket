--[[
    State of Deliverance Territorial Lottery - configuration
    ---------------------------------------------------------
    Everything in this file is a DEFAULT. Once the server has started with
    oxmysql available, the admin panel (/lotteryadmin) stores its own copy of
    the economy settings in the database, and the database copy wins.
    To reset to these defaults, delete the 'settings' row from the
    `sod_lottery_kv` table (or use the "Restore defaults" button in the panel).

    All money is the fictional in-game currency of the server.
]]

Config = {}

-- 'auto' | 'vorp' | 'rsg' | 'standalone'
-- auto checks for vorp_core, then rsg-core, and falls back to standalone.
Config.Framework = 'auto'

-- Reference ticket price that the FIXED tier payouts and the jackpot seed are
-- written for. Actual payout = payout x (ticketPrice / basePrice), rounded to
-- cents, so changing the ticket price scales every prize proportionally and
-- the return-to-player percentages stay the same. Half-back (price_ratio) and
-- the loss-to-jackpot feed already follow the price.
Config.basePrice = 10

-- Debug prints in server/client console.
Config.Debug = false

-- Create the database tables automatically on start if they are missing
-- (same statements as sql/install.sql).
Config.AutoCreateTables = true

---------------------------------------------------------------------------
-- Ticket item
---------------------------------------------------------------------------
Config.Item = {
    name  = 'lottery_ticket',   -- register this item in your inventory (see README)
    label = 'Deliverance Fortune Ticket',
    -- When the ticket is bought in a general store, the STORE takes the money.
    -- If true, using a store-bought ticket is booked in the ledger as money in
    -- (at the current ticket price) and split into house / jackpot / prize backing.
    storeSoldCountsAsRevenue = true,
}

-- Direct sale (OFF by default). The intended purchase path is the general
-- store: players buy `lottery_ticket` items and scratch them from inventory.
-- Set enabled = true only if you also want the /buyticket command and the
-- post-office counters (G prompt). Direct sales are charged in CASH ON HAND only.
Config.DirectSale = {
    enabled = false,
    command = 'buyticket',     -- set to false to disable the command
    -- Lottery counters: walk up and press the key to buy and scratch at once.
    useLocations = true,
    interactKey = 0x760A9C6F,  -- G key
    interactDistance = 1.6,
    locations = {
        { label = 'Valentine Post Office',  coords = vector3(-178.90, 626.70, 114.09) },
        { label = 'Saint Denis Post Office', coords = vector3(2731.60, -1402.40, 46.18) },
        { label = 'Blackwater Post Office', coords = vector3(-875.00, -1328.70, 43.95) },
    },
}

---------------------------------------------------------------------------
-- Sounds (html/sounds/). Losing-ticket sound: 'sadtrombone' (default) or 'fart'.
-- Also editable in the admin panel (stored with the other settings).
-- Wins play win.wav (cha-ching); three Oil Pumps add yeehaw.wav after it;
-- scratch.wav plays while scratching and on "Reveal all".
---------------------------------------------------------------------------
Config.Sounds = {
    lose = 'sadtrombone',
}

---------------------------------------------------------------------------
-- Economy defaults (admin-editable, persisted in DB)
---------------------------------------------------------------------------
Config.Defaults = {
    salesEnabled = true,
    loseSound    = Config.Sounds.lose, -- 'sadtrombone' | 'fart'
    ticketPrice  = 10.0,    -- $ per ticket (prizes scale by ticketPrice / Config.basePrice)
    printRun     = 120000,  -- size of a virtual print run; loss weight = printRun - sum(tier weights)

    -- Split of every ticket price (percent of price). The remainder
    -- (100 - houseEdge - jackpotPercent - lose% x lossContributionPct) "backs" the instant prizes.
    houseEdge      = 30.0,  -- retained as server revenue (removed from the economy)
    -- Percent of EVERY ticket fed into the progressive pot. Default 0, because
    -- the loss contribution below replaces it (see jackpot.lossContributionPct).
    jackpotPercent = 0.0,

    -- If true, FIXED instant payouts are multiplied so that fixed + half-back
    -- prizes together equal the prize-backing share exactly, i.e. the configured
    -- edge holds. price_ratio tiers keep their ratio; only 'fixed' tiers scale.
    autoScalePayouts = false,

    -- Which jackpot value to use when computing the progressive tier's
    -- contribution to RTP in the admin panel: 'current' pot or the 'seed'.
    rtpJackpotBasis = 'current',

    -- Prize tiers. plate = symbol id (shared/plates.lua).
    -- type 'fixed'       : pays `payout` dollars AT THE BASE PRICE (Config.basePrice),
    --                      scaled by ticketPrice / basePrice.
    -- type 'price_ratio' : pays `ratio` x the current ticket price (0.5 = "half back",
    --                      $5 on a $10 ticket); follows price changes, never auto-scaled.
    -- type 'progressive' : pays the whole progressive jackpot pot (payout ignored),
    --                      then the pot is reseeded.
    -- weight = winning tickets per print run.
    -- Defaults: 61,200 / 120,000 = exactly 51% of tickets win something, 49% lose.
    -- Half-back weight = 61200 - (8000+10000+14000+300+12+2) = 28886.
    tiers = {
        { plate = 'SILVER_DOLLAR', type = 'price_ratio', ratio = 0.5, payout = 0, weight = 28886 }, -- half back
        { plate = 'HORSESHOES',  type = 'fixed',       payout = 1,    weight = 8000  },
        { plate = 'COWBOY_HAT',  type = 'fixed',       payout = 5,    weight = 10000 },
        { plate = 'TOP_HAT',     type = 'fixed',       payout = 10,   weight = 14000 },
        { plate = 'GOLD_NUGGET', type = 'fixed',       payout = 100,  weight = 300   },
        { plate = 'MOONSHINE',   type = 'fixed',       payout = 1000, weight = 12    }, -- high jackpot tier
        { plate = 'OIL_PUMP',    type = 'progressive', payout = 0,    weight = 2     }, -- top jackpot: wins the pot
    },

    jackpot = {
        seed = 2500.0,            -- pot value after every win / on first start
        -- Percent of each LOSING ticket's price added to the Oil Pump pot (0-100).
        -- Wins (including half-back) add nothing. Pot money is eventually paid back
        -- to players, so a higher value weakens the long-run money sink.
        lossContributionPct = 50,
        drawEnabled = true,       -- periodic draw among ticket entries
        drawMode = 'interval',    -- 'interval' (every N hours) or 'schedule' (fixed daily times)
        intervalHours = 24,
        schedule = { '20:00' },   -- server-local "HH:MM" times, used when drawMode = 'schedule'
        minPlayers = 3,           -- distinct entrants needed for a draw, otherwise roll over
        minTickets = 10,          -- entries needed for a draw, otherwise roll over
        maxPot = 0,               -- 0 = no cap; otherwise the pot stops growing past this
    },
}

---------------------------------------------------------------------------
-- Anti-abuse
---------------------------------------------------------------------------
Config.Security = {
    purchaseCooldownMs = 4000,   -- min time between ticket purchases per player
    maxEventsPerWindow  = 12,    -- any lottery event; more than this per window is ignored
    eventWindowMs       = 5000,
    ticketTimeoutSec    = 180,   -- unclaimed tickets are auto-settled (prize paid) after this
    dropOnSpam          = false, -- kick players who keep spamming events
}

---------------------------------------------------------------------------
-- Admin permissions
---------------------------------------------------------------------------
Config.Admin = {
    command = 'lotteryadmin',
    ace = 'sod_lottery.admin',            -- add_ace group.admin sod_lottery.admin allow
    vorpGroups = { 'admin', 'superadmin' }, -- VORP user group names allowed
    rsgPermissions = { 'admin', 'god' },     -- RSG permission names allowed
    recentWinnersShown = 15,
}

---------------------------------------------------------------------------
-- Admin money commands (server-side, ACE `Config.Admin.ace` only; console allowed)
--   /givemoney [playerId] [amount]    /takemoney [playerId] [amount]
-- Rename them if they clash with your framework's own admin commands.
---------------------------------------------------------------------------
Config.AdminMoney = {
    enabled = true,
    giveCommand = 'givemoney',
    takeCommand = 'takemoney',
    maxAmount = 10000,     -- max $ per single command
    takeMode = 'refuse',   -- 'refuse' if the target has less than asked, or 'partial' (take what they have)
    chatSuggestions = true,
}

-- Hard bounds enforced server-side on every admin save.
Config.Limits = {
    priceMin = 0.25, priceMax = 1000,
    payoutMax = 1000000,
    ratioMin = 0.01, ratioMax = 10,
    printRunMin = 100, printRunMax = 100000000,
    maxTiers = 12,
    seedMax = 1000000,
    intervalHoursMin = 1, intervalHoursMax = 24 * 30,
}

-- How long win/loss banners and jackpot telegrams stay up (ms).
Config.UI = {
    telegramMs = 14000,
    toastMs = 6000,
}
