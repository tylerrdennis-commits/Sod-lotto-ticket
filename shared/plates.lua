-- Ticket symbols ("plates"). Art lives in html/index.html as inline SVG <symbol>s
-- with id "sym-<ID>". `jackpot = true` symbols get special win styling and a
-- territory-wide announcement when matched.
Plates = {
    SILVER_DOLLAR = { label = 'Silver Dollar', jackpot = false },
    HORSESHOES  = { label = 'Horseshoes',      jackpot = false },
    COWBOY_HAT  = { label = 'Cowboy Hat',      jackpot = false },
    TOP_HAT     = { label = 'Top Hat',         jackpot = false },
    GOLD_NUGGET = { label = 'Gold Nugget',     jackpot = false },
    MOONSHINE   = { label = 'Moonshine Still', jackpot = true  },
    OIL_PUMP    = { label = 'Oil Pump',        jackpot = true  },
}

-- Loss filler symbol (never part of a prize tier).
Plates.FILLER = 'TUMBLEWEED'

-- Ordered list for UI dropdowns.
PlateOrder = { 'SILVER_DOLLAR', 'HORSESHOES', 'COWBOY_HAT', 'TOP_HAT', 'GOLD_NUGGET', 'MOONSHINE', 'OIL_PUMP' }
