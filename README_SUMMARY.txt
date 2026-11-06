DELIVERANCE FORTUNE - TERRITORIAL LOTTERY
Summary for State of Deliverance server staff
================================================================

1) REASSURANCES
----------------------------------------------------------------
- Players buy the "Deliverance Fortune Ticket" (item: lottery_ticket) from
  the general store as a normal inventory item. The store is the ONLY way to
  buy one: the post-office counters and /buyticket are switched off by
  default (Config.DirectSale.enabled = false), and the ticket has no buy button.
- Using the ticket from the inventory opens it as a small card in the
  lower-right corner (480x360 at 1080p, about a quarter of the screen); the
  game stays visible around it. Players scratch its 3 plates with the mouse
  or press "Reveal all". Match 3 to win.
- "Flip for odds" turns the card over to a printed back showing every
  prize, its odds and the return to player, taken from the live settings.
- Tickets stack, so a player can carry a pile of them:
    VORP: install/vorp_items.sql sets limit = 50.
    RSG : install/rsg_items.lua.txt sets unique = false and weight 10.
          RSG has no per-item cap; 50 tickets weigh 500.
- Each scratch removes exactly one ticket. The server rolls the result and
  pays any prize.
- The server handles every money move and every roll. The player's screen
  only draws the ticket, so a player cannot fake a win.
- Anti-abuse:
    - One active ticket at a time.
    - A purchase cooldown (4 s).
    - A rate limit on all lottery events, with spam logged and an optional kick.
    - A claim must match the serial the server issued. Forged or stale claims
      are ignored.
    - Abandoned tickets are paid out automatically, and disconnects queue
      the winnings.
- Works with VORP Core and RSG Core (detected automatically), and has a
  standalone fallback.
- The admin panel (/lotteryadmin) opens only for ACE sod_lottery.admin or the
  framework admin groups. Every admin action is checked again by the server.
- Sounds: foil scratch while scratching and on "Reveal all"; cha-ching on
  wins; a "yee-haw" on top of the cha-ching for the Oil Pump jackpot; sad
  trombone on losses (or the fart sound, which you can choose in config or
  the admin panel).

2) HOW THE ODDS WERE SET (defaults, $10 ticket, print run 120,000)
----------------------------------------------------------------
51% of tickets win something and 49% win nothing.
(61,200 winning tickets and 58,800 losing tickets per 120,000.)

  Symbol            Payout                       Weight   Odds
  Silver Dollar     half back: 50% of price ($5)  28,886  1 in 4.15
  Horseshoes        $1                            8,000  1 in 15
  Cowboy Hat        $5                           10,000  1 in 12
  Top Hat           $10                          14,000  1 in 8.6
  Gold Nugget       $100                            300  1 in 400
  Moonshine Still   $1,000                           12  1 in 10,000
  Oil Pump          progressive jackpot pot           2  1 in 60,000
  Tumbleweed        nothing (loss filler)        58,800  49%

How each $10 ticket is divided: 30% house edge ($3) is kept and removed
from the economy. On a LOSING ticket, 50% of the price ($5) goes to the
Oil Pump pot (loss-to-jackpot). Winning tickets, including half-back, add
nothing to the pot. Whatever is left backs the instant prizes. The old
"10% of every ticket to the pot" now defaults to 0% but can still be
changed. The pot starts at a $2,500 seed and pays out on
three Oil Pumps, or in the periodic draw among ticket entries (every 24 h
by default, needing at least 3 entrants and 10 tickets).

Return to player (Oil Pump valued at the $2,500 seed):
                              Auto-scale OFF (default)   Auto-scale ON
  Instant prizes               32.04%                     45.08%
  Instant incl. Oil Pump seed  32.45%                     45.50%
  Fed to the pot               24.50%                     24.50%
  Long-run return*             56.95%                     70.00%
  Instant house edge           67.55%                     54.50%
  Long-run house edge          43.05%                     30.00%
  * Money fed to the pot is EVENTUALLY PAID BACK to players (Oil Pump hits
    and draws), plus the seed put back after each hit. So the long-run
    figure is the true return, and a higher loss-to-jackpot % weakens the
    long-run money sink.
With auto-scale on, fixed prizes become x1.652 ($1.65, $8.26, $16.52,
$165.24, $1,652.38). The half-back prize stays at 50% of the price.
A 200,000-ticket simulation gave a 51.05% win rate, a 32.13% instant
return, and 24.48% of sales fed to the pot.

3) HOW TO CHANGE THE ODDS
----------------------------------------------------------------
Prizes scale with the ticket price. Payouts are written at the $10 base
price (Config.basePrice), so a $20 ticket pays double: Silver Dollar $10,
Horseshoes $2, Cowboy Hat $10, Top Hat $20, Gold Nugget $200, Moonshine
Still $2,000, Oil Pump seed $5,000. A $5 ticket pays half. The return to
player % stays the same at any price. In the admin panel, enter payouts at
the base price; the "Pays now" column shows the real prize.

Type /lotteryadmin in game. You can edit: ticket price, print run, every
prize tier (symbol, type, payout or price ratio, weight; add or remove
tiers), house edge %, pot % (every ticket), loss-to-jackpot % (losing
tickets, 0-100, default 50), jackpot seed and cap, and draw timing (every
N hours or daily times) with minimum entrants and tickets. You can also
open or close sales, choose the loss sound, and run a draw now. The return
to player, house edge, and win/lose % update live as you type, with a
warning if the return goes above 100% or the edge is not met. Press
"Enter in ledger" to save; "Restore defaults" loads the config values.

Auto-scale sets the fixed payouts so that the configured house edge is
met EXACTLY over the long run. With the default tiers it scales them UP
(x1.65), so players
get more back and the money sink is weaker. It would only scale them down
if your tiers paid more than the edge allows. For a STRONGER sink, keep
auto-scale off and lower payouts or weights, or raise the house edge.

Tip: players stay happy when tickets win often, even if the wins are small.
Keep the win rate around 40-55% with a visible jackpot, and aim for a
total return of roughly 30-60%. Below that, tickets start to feel like a
plain tax.

4) STAFF: CASH ON HAND ONLY
----------------------------------------------------------------
Tickets are paid ONLY from cash on hand, and every prize (half-back,
fixed prizes, Oil Pump pot, draw winnings) is paid ONLY to cash on hand.
The bank is never used. If a player is short on cash, the purchase is
refused with a notice. /givemoney and /takemoney also use cash only.
This is hard-coded (VORP currency 0, RSG 'cash'). For store-bought
tickets, set the general store to charge cash.

5) STAFF: ADMIN MONEY COMMANDS
----------------------------------------------------------------
Usage:     /givemoney [playerId] [amount]    /takemoney [playerId] [amount]
Examples:  /givemoney 12 250                 /takemoney 12 49.50
           (from the server console, leave out the slash: givemoney 12 250)
Permission: ACE sod_lottery.admin only, or the server console.
Limits:    The target must be online. The amount must be positive, have at
           most 2 decimals, and be no more than $10,000 per command
           (Config.AdminMoney.maxAmount).
           takemoney never sends a balance negative: by default it refuses
           if the player has too little (takeMode = 'partial' takes what
           they have instead).
Logging:   Every use is written to the server console and to the
           sod_lottery_audit table: admin, target, amount, and cash before
           and after. Admin and target both get a notification.
Names:     You can rename the commands in Config.AdminMoney if they clash
           with your framework's own money commands, or switch them off
           with enabled = false.

6) WHY THESE ODDS / MAKING IT A STRONGER MONEY SINK
----------------------------------------------------------------
The odds are modelled loosely on real-world lotteries. Those typically pay
roughly 50-60% of ticket sales back to players as prizes, often with a
frequent small "money back" prize so that many tickets win something.
Our 51% win share and the half-back tier follow that pattern.

The actual return, checked against the defaults ($10 ticket, 30% house
edge, 50% of each losing ticket to the pot, $2,500 seed):
  Auto-scale OFF (default): instant prizes 32.04%. Including the pot
    (eventually paid back) and seed, the long-run return is 56.95%, and the
    long-run house edge is 43.05%.
  Auto-scale ON: instant prizes 45.08%, long-run 70.00%, edge 30.00%.
So the shipped default lands INSIDE the 50-60% real-world range, but only
over the long run, once the jackpot money is paid back. The instant prizes
alone (32%) are well below it. Auto-scale ON goes above the range, to 70%.

To make it a STRONGER sink (lower return to player):
  a) Keep auto-scale OFF.
       Admin panel: "Auto-scale payouts to hold edge"
       Config key:  autoScalePayouts = false
  b) Lower the half-back prize, or how often it hits. Lowering the
     weight also lowers the 51% win share.
       Admin panel: Prize schedule, Silver Dollar row, "Payout $ / ratio"
                    or "Weight"
       Config key:  tiers[SILVER_DOLLAR].ratio (0.5) / .weight (28886)
  c) Reduce the other prizes.
       Admin panel: "Payout $" and "Weight" columns
       Config key:  tiers[...].payout / .weight
  d) Lower the pot feed: everything fed to the pot is eventually paid
     back to players.
       Admin panel: "Loss-to-jackpot % (losing tickets)" and
                    "To pot from every ticket %"
       Config key:  jackpot.lossContributionPct (50) / jackpotPercent (0)
  With auto-scale ON, raising "House edge %" (houseEdge) lowers the
  return instead.

Example settings (all other values default; computed by the resource's own
RTP maths, Oil Pump valued at the seed; "Long-run" includes pot + seed):
  Setting                                   Win %   Instant  Long-run  LR edge
  Default, auto-scale off                   51.00%  32.45%   56.95%    43.05%
  Default, auto-scale on                    51.00%  45.50%   70.00%    30.00%
  Auto-scale on, house edge 40%             51.00%  35.50%   60.00%    40.00%
  Auto-scale on, house edge 50%             51.00%  25.50%   50.00%    50.00%
  Loss-to-jackpot 50% -> 25%                51.00%  32.45%   44.70%    55.30%
  Loss-to-jackpot 50% -> 0%                 51.00%  32.45%   32.45%    67.55%
  Half-back ratio 0.5 -> 0.25               51.00%  26.43%   50.93%    49.07%
  Half-back 0.25 + other payouts halved     51.00%  16.43%   40.93%    59.07%
  Half-back weight 28886 -> 14443           38.96%  26.43%   56.95%    43.05%
(Halving the half-back weight lowers the instant return. More tickets
then lose, though, which feeds more into the pot, so the long-run return
stays the same unless you also lower the loss-to-jackpot %.)
The admin panel shows these figures live as you edit. The Oil Pump share
grows as the pot grows: about 0.42% at the $2,500 seed.

7) STAFF: ITEM IMAGES
----------------------------------------------------------------
  install/images/vorp/lottery_ticket.png  (96x96)  -> vorp_inventory/html/img/items/
  install/images/rsg/lottery_ticket.png   (100x100) -> rsg-inventory/html/images/
  install/images/lottery_ticket_192.png   (192x192)  sharper version; rename it
                                            to lottery_ticket.png if wanted
  install/images/lottery_ticket_shop.png  (512x512)  shop display image; the
                                            path depends on your store script
Both inventories find the image by the item name (lottery_ticket.png).
Neither framework documents a fixed pixel size; any square PNG works.
