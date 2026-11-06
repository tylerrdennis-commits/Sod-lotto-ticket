-- Every player-facing string lives here. Edit freely; %s / %d are placeholders.
Strings = {
    brand          = 'State of Deliverance',
    lotteryName    = 'Deliverance Territorial Lottery',
    ticketName     = 'Deliverance Fortune Ticket',

    -- notifications
    salesClosed    = 'The Territorial Lottery office is closed for the present.',
    noMoney        = 'A Fortune Ticket costs $%s in cash on hand, friend. The Lottery takes no bank notes.',
    cooldown       = 'Easy, partner. The clerk is still inking your last ticket.',
    activeTicket   = 'Finish scratching the ticket in your hand first.',
    bought         = 'One Fortune Ticket, $%s. May Providence smile upon you.',
    won            = 'Three %s! The Lottery pays you $%s.',
    lost           = 'Naught but tumbleweed. Better fortune next time.',
    jackpotWon     = 'THREE OIL PUMPS! You struck the Progressive Jackpot of $%s!',
    pendingPaid    = 'The Lottery office held $%s in winnings for you. Paid in full.',
    notAdmin       = 'You are not on the Lottery Commission.',
    saved          = 'The Commission ledger has been amended.',
    invalid        = 'The Commission rejected those figures: %s',
    pressToBuy     = 'Press [G] - Buy a Fortune Ticket ($%s)',
    drawSkipped    = 'Jackpot draw postponed: not enough entrants. The pot rolls over.',

    -- telegrams (announcements)
    telegramHead   = 'WESTERN TERRITORIAL TELEGRAPH CO.',
    telegramJackpotInstant = '%s of this Territory scratched three Oil Pumps and claims the Progressive Jackpot of $%s. STOP. Pot reseeded at $%s. STOP.',
    telegramMoonshine      = '%s found three Moonshine Stills upon a Fortune Ticket and collects $%s. STOP.',
    telegramDraw           = 'The Lottery Commission has drawn the Progressive Jackpot. %s wins $%s from %d entries. STOP. Next pot opens at $%s. STOP.',
    telegramSign   = 'By order of the State of Deliverance Lottery Commission',

    -- ticket UI copy (sent to NUI)
    ui = {
        title     = 'Deliverance Fortune',
        subtitle  = 'Territorial Lottery of the State of Deliverance',
        year      = 'Anno 1899',
        rules     = 'Scratch all three plates. Match 3 alike to win the sum shown. 3 Silver Dollars return half your stake; 3 Oil Pumps strike the Progressive Jackpot.',
        flavour   = 'Licensed by the Commission. Void where Providence forbids. Not redeemable for land, livestock, or spouses.',
        scratch   = 'SCRATCH HERE',
        revealAll = 'Reveal all',
        close     = 'Fold & pocket',
        win       = 'A WINNER!',
        lose      = 'NOT A WINNER',
        jackpot   = 'PROGRESSIVE JACKPOT!',
        bigWin    = 'MOONSHINE FORTUNE!',
        potLabel  = 'Progressive pot',
        serial    = 'No.',
        prizeKey  = 'Prize schedule',
        waiting   = 'The clerk is checking your ticket...',
        flip      = 'Flip for odds',
        flipBack  = 'Flip back',
        backTitle = 'Odds & Conditions',
        match3    = 'Match 3 to win',
    },
}

function L(key, ...)
    local s = Strings[key] or key
    if select('#', ...) > 0 then return s:format(...) end
    return s
end
