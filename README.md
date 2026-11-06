# Deliverance Fortune — State of Deliverance Territorial Lottery

> Maintaining this resource? Read `AGENT_NOTES.txt` first.

A scratch-ticket lottery for the **State of Deliverance** RedM server (1899). It works as an
in-game **money sink**: every ticket takes in-game cash out of the economy, a share goes to a
progressive jackpot, and the rest backs small instant prizes. Fictional in-game currency only.

* Server-authoritative: the server takes the money, rolls the outcome with server RNG, builds
  the ticket grid and pays out. Scratching is cosmetic and can't change a result.
* Frameworks: **VORP Core**, **RSG Core**, or standalone (auto-detected, see `server/bridge.lua`).
* Persistence: **oxmysql** (falls back to memory with a console warning if oxmysql isn't running).
* Lottery Commission panel (`/lotteryadmin`) for admins: price, prize tiers, edge, jackpot,
  draws, live RTP, and the ledger. Players only ever see the ticket.

## The ticket

One row of **3 foil plates**. Scratch with the mouse, or press **Reveal all**. **Match 3 to win**: all three
plates showing the same symbol win that tier. A losing ticket never shows three of a kind (it shows mixed
symbols and tumbleweed, sometimes a near-miss pair). The server rolls the result; the plates only display it.

The card is a compact overlay. It's designed at **480×360 px for a 1920×1080 screen** (a quarter of the
screen width, a third of its height), sits in the **lower-right corner** with a 3vh margin, scales with
the screen resolution (minimum ×0.6), and has a transparent background so the game stays visible around it.

**Flip for odds** turns the card over (CSS 3D flip) to a printed back. It shows the ticket price, "Match 3
to win", every symbol's prize and its odds as "1 in N", the win/lose %, the return to player, and a fine-print
line about how the jackpot is fed. All of it is computed from the **live server settings** and sent with
each ticket, so it stays correct after admin changes (auto-scaled payouts are shown when auto-scale is on).
Players can flip before or after scratching, and it doesn't affect the result. The front shows no odds.

Default tiers:

| Symbol | Default prize | Weight / 120,000 | Odds |
|---|---|---|---|
| Silver Dollar ("half back") | 50% of ticket price ($5 at $10) | 28,886 | 1 in 4.15 |
| Horseshoes | $1 | 8,000 | 1 in 15 |
| Cowboy Hat | $5 | 10,000 | 1 in 12 |
| Top Hat | $10 | 14,000 | 1 in 8.6 |
| Gold Nugget | $100 | 300 | 1 in 400 |
| **Moonshine Still** (high jackpot tier) | $1,000 | 12 | 1 in 10,000 |
| **Oil Pump** (top jackpot) | **Progressive pot** | 2 | 1 in 60,000 |
| Tumbleweed (loss filler) | nothing | 58,800 | 49% of tickets |

The winning weights add up to 61,200 of 120,000, so **exactly 51% of tickets win something**
and 49% win nothing.

**Prizes scale with the ticket price.** Fixed payouts (and the jackpot seed) are written for
`Config.basePrice = 10`. The server pays `payout × ticketPrice / basePrice`, rounded to cents, with
auto-scale applied on top. Doubling the price doubles every prize, and the return percentages stay
identical:

| Tier | $5 ticket | $10 ticket | $20 ticket |
|---|---|---|---|
| Silver Dollar (half back) | $2.50 | $5 | $10 |
| Horseshoes | $0.50 | $1 | $2 |
| Cowboy Hat | $2.50 | $5 | $10 |
| Top Hat | $5 | $10 | $20 |
| Gold Nugget | $50 | $100 | $200 |
| Moonshine Still | $500 | $1,000 | $2,000 |
| Oil Pump seed | $1,250 | $2,500 | $5,000 |

The loss-to-jackpot feed is a percentage of the price, so it already follows the price. An existing
pot isn't changed when the price changes (it's money already collected); only future reseeds use the
new seed. In the admin panel, tier payouts are entered at the base price, and the "Pays now" column
shows the actual prize at the price currently typed in.

The half-back tier uses the tier type `price_ratio` (`ratio = 0.5`), so it always pays half the
current ticket price. Tier types are `fixed` (a dollar amount), `price_ratio` (a multiple of the
price) and `progressive` (the whole pot).

Moonshine Still and Oil Pump are *jackpot symbols*: their wins get special styling and a
territory-wide telegram. Three Oil Pumps pay the whole progressive pot, and the pot is then reseeded.
All tiers can be changed in the admin panel.

## Install

1. Copy `sod_lottery/` into your `resources` folder.
2. **Database**: import `sql/install.sql`. You can skip this if `Config.AutoCreateTables = true`
   (the default), because the tables are then created on start.
3. **server.cfg**: start it after oxmysql and your framework:
   ```cfg
   ensure oxmysql
   ensure vorp_core        # or rsg-core
   ensure vorp_inventory   # VORP only
   ensure sod_lottery

   # Commission (admin) permission through ACE. Framework admins also work, see config.
   add_ace group.admin sod_lottery.admin allow
   ```
4. **Ticket item** (`lottery_ticket`). Images are in `install/images/`. Both inventories load
   `<item>.png` by name; no fixed pixel size is documented, so these sizes are a reasonable choice:
   * `install/images/vorp/lottery_ticket.png` (96×96) → `vorp_inventory/html/img/items/lottery_ticket.png`
   * `install/images/rsg/lottery_ticket.png` (100×100) → `rsg-inventory/html/images/lottery_ticket.png`
   * `install/images/lottery_ticket_192.png` (192×192), a sharper version if your inventory shows large icons (rename it to `lottery_ticket.png`)
   * `install/images/lottery_ticket_shop.png` (512×512), a shop display image. Where it goes depends on your store script (see `install/store_examples.txt`).
   * **VORP**: run `install/vorp_items.sql` (sets `limit` = 50, so a player can carry 50 tickets), then copy `install/images/vorp/lottery_ticket.png` to `vorp_inventory/html/img/items/`.
   * **RSG**: add the entry in `install/rsg_items.lua.txt` (`unique = false` makes it stack, weight 10 each) to `rsg-core/shared/items.lua`, then copy `install/images/rsg/lottery_ticket.png` to `rsg-inventory/html/images/`.
5. **General store**: add the item to your store's product list (see `install/store_examples.txt`
   for rsg-shops and vorp_stores). Keep the store price equal to the lottery ticket price.
6. The store is the **only** purchase path by default. The post-office counters (G prompt) and
   `/buyticket` are **off** (`Config.DirectSale.enabled = false`). If you switch them on, they charge cash on hand only.
   The NUI has no buy button.

### Ways to get a ticket

* **Store-bought item**: the store takes the money, and the player uses the item to scratch it.
  When it's used, the ticket is booked in the ledger at the current price and split as below
  (`Config.Item.storeSoldCountsAsRevenue`).
* **Direct (off by default)**: `/buyticket` or a lottery counter, only if `Config.DirectSale.enabled = true`. The server removes the price from the player's cash on hand.

## Money flow (per ticket)

```
price ──┬─ house edge %            → retained, removed from the economy (ledger: house revenue)
        ├─ pot % (every ticket)    → progressive pot   [jackpotPercent, default 0]
        ├─ loss-to-jackpot %       → progressive pot, LOSING tickets only [jackpot.lossContributionPct, default 50]
        └─ remainder               → backs instant prizes; anything not paid out is also removed
```

**Loss-to-jackpot** (admin panel "Loss-to-jackpot % (losing tickets)", 0–100, step 1, default 50):
this percentage of each losing ticket's price goes into the Oil Pump pot. Winning tickets, including
half-back, add nothing. It **replaces** the old 10%-of-every-ticket feed as the default (`jackpotPercent`
now defaults to 0 but can still be changed). The reason is that feeding the pot only from losing tickets
makes the jackpot grow from "bad luck" money and never takes a cut from a winner's ticket, and adding it
on top of the old 10% would push the long-run return to about 67%. The pot cut is taken before the house
cut, so if edge + pot cuts add up to more than 100% of a losing ticket, the house keeps less on that ticket
(the ledger records the real split). Money fed to the pot is **eventually paid back to players**, so a
higher percentage weakens the long-run money sink.

With `autoScalePayouts = true`, fixed payouts are multiplied so their expected value matches the
backing share exactly, which makes the configured house edge hold precisely.

### Default economics ($10 ticket, 30% edge, pot fed by 50% of each losing ticket, $2,500 seed)

| | Auto-scale OFF (default) | Auto-scale ON |
|---|---|---|
| Win / lose | 51% / 49% | 51% / 49% |
| Half-back EV | $1.20 (12.04%) | $1.20 (12.04%) |
| Fixed prizes EV | $2.00 (20.00%) | $3.30 (33.04%), fixed tiers ×1.652 |
| **Instant prizes (paid on the spot)** | **32.04%** | **45.08%** |
| Instant incl. Oil Pump valued at seed | 32.45% | 45.50% |
| Fed to pot (49% × 50%) | 24.50% | 24.50% |
| **Long-run return (pot paid back + seed)** | **56.95%** | **70.00%** |
| Instant house edge | 67.55% | 54.50% |
| **Long-run house edge** | **43.05%** | **30.00%** |

* Long-run return = instant prizes + money fed to the pot + seed money put back after each Oil Pump hit.
  Reseeds after periodic draws add a bit more on top.
* With auto-scale on, only `fixed` tiers scale ($1.65 / $8.26 / $16.52 / $165.24 / $1,652.38) so that the
  long-run return equals exactly 100% − house edge. The half-back tier stays at 50% of the price.
* A 200,000-ticket simulation (3-plate layout, defaults) gave a **51.05% win rate**, a **32.13% instant return**
  (theory 32.04%), and **24.48% of sales fed to the pot** (theory 24.50%).

The admin panel recomputes these figures live as you type. It warns when RTP is above 100% or the
configured edge isn't met. The **RTP jackpot basis** setting decides whether the Oil Pump tier is
valued at the current pot or at the seed.

## Sounds

All sounds are original, generated procedurally offline in Python, and live in `html/sounds/`:

| File | When it plays |
|---|---|
| `scratch.wav` (0.45 s) | while scratching the foil (retriggered about every 330 ms while dragging) and once on **Reveal all** |
| `win.wav` (cha-ching) | any winning ticket |
| `yeehaw.wav` (1.45 s) | three Oil Pumps (progressive jackpot), right after the cha-ching |
| `sadtrombone.wav` (2.5 s) | losing ticket, the default (`Config.Sounds.lose = 'sadtrombone'`) |
| `fart.wav` | losing ticket, if the loss sound is set to `'fart'` (config or admin panel) |

The NUI volume is 0.6 by default.

## Progressive jackpot draw

* Every ticket is one entry in the current draw period.
* The draw runs **every N hours** or at **daily times** (`20:00, 23:30`, server local time).
* If there are fewer than *min. entrants* or *min. tickets*, the draw is postponed and the pot
  and entries roll over.
* The winner is drawn uniformly from the period's entries with server RNG and is paid at once if
  online. Otherwise the money is queued in `sod_lottery_pending` and paid when they next load a character.
* A telegram goes out to all players, and the pot is reseeded.
* Admins can **Draw now** (optionally ignoring the minimums).

## Admin panel — `/lotteryadmin`

The ledger shows the live instant return, long-run return, both house edges, the average pot feed, and the win/lose %.

Opens the Commission ledger for ACE `sod_lottery.admin`, VORP groups in `Config.Admin.vorpGroups`,
or RSG permissions in `Config.Admin.rsgPermissions`. Each panel event checks permission again on the
server, and every value is validated server-side (ranges, unique symbols, at most one pot tier,
weights within the print run, schedule format). Saved settings go into `sod_lottery_kv` and
override `config.lua`. **Restore defaults** loads the config values, and you press *Enter in ledger* to keep them.

The ledger shows tickets sold, money in, instant and jackpot payouts, house revenue retained,
seed money injected, net money removed from the economy, actual RTP to date, the current pot, the
next draw, and recent winners.

## Cash on hand only

All lottery money uses **cash on hand**, never the bank. This is hard-coded in `server/bridge.lua`
and can't be configured. Ticket purchases, every payout (half-back, fixed prizes, the Oil Pump pot,
draw winnings, queued winnings) and `/givemoney` / `/takemoney` use VORP currency type 0 or
RSG money type `'cash'`. The balance is checked before anything is removed. If a player doesn't have
enough cash, the purchase is refused with a notice, and there is no fallback to the bank.
Store-bought tickets are charged by your store script, so set that store to cash too.

## Admin money commands

```
/givemoney [playerId] [amount]     e.g. /givemoney 12 250
/takemoney [playerId] [amount]     e.g. /takemoney 12 49.50
```
* **Permission**: ACE `sod_lottery.admin` only (framework groups are not enough), or the server
  console (source 0). Run from the console without the slash: `givemoney 12 250`.
* **Checks**: the target must be online with a character loaded. The amount must be positive, with
  at most 2 decimals, and no more than `Config.AdminMoney.maxAmount` (default $10,000).
  `takemoney` never sends a balance negative. With `takeMode = 'refuse'` (default) it refuses if the
  player has less than asked; with `'partial'` it takes what they have.
* Money moves through the VORP or RSG bridge (cash).
* Both the admin and the target get a notification.
* **Logging**: every use is printed to the console with the admin, target, amount, and cash before
  and after. It is also stored in the `sod_lottery_audit` table.
* **Config**: `Config.AdminMoney.enabled`, `giveCommand`, `takeCommand` (rename them if they clash
  with your framework's admin commands), `maxAmount`, `takeMode`, `chatSuggestions`.

## Security notes

* One ticket in hand per player. Purchases have a cooldown (`Config.Security.purchaseCooldownMs`),
  and every lottery event is rate-limited (spammers are logged and can optionally be dropped).
* A claim must match the serial of the ticket the server issued to that player. Forged or stale claims are ignored.
* A ticket that is never claimed is paid automatically after `ticketTimeoutSec`. On disconnect, the
  winnings are queued. On resource stop, tickets in hand are paid through the framework.
* A progressive win resets the pot **at purchase time**, so two players can never win the same pot.
  Draws advance the period and reseed before paying.

## Files

```
sod_lottery/
├── fxmanifest.lua
├── README.md
├── shared/config.lua      defaults, documented
├── shared/plates.lua      symbol list (ids, labels, jackpot flags)
├── locales/strings.lua    every player-facing string and the ticket copy
├── client/main.lua        NUI bridge, lottery counters
├── server/bridge.lua      VORP / RSG / standalone adapter (money, items, permissions)
├── server/db.lua          oxmysql layer with in-memory fallback
├── server/economy.lua     validation, RTP maths, RNG roll, grid builder
├── server/main.lua        selling, settlement, anti-abuse, pending payouts
├── server/jackpot.lua     progressive draw scheduler
├── server/admin.lua       Commission panel events
├── html/                  index.html (inline SVG art), style.css, app.js, sounds/
├── sql/install.sql
├── README_SUMMARY.txt   short staff summary
├── AGENT_NOTES.txt      maintainer notes (layout, key settings, gotchas)
└── install/               item SQL/registrations, store examples, images/ (inventory icons, shop image)
```

## Previewing the UI in a browser

Open `html/index.html?mock=ticket` (also `&stage=full|none`, `&win=OIL_PUMP|MOONSHINE|SILVER_DOLLAR|TOP_HAT|loss`, `&back=1` for the odds side),
`?mock=telegram` or `?mock=admin`. Mock mode uses sample data and never calls the game.

## Customising

* Text and flavour: `locales/strings.lua`.
* Symbols: art in `html/index.html` (`<symbol id="sym-ID">`), and metadata in `shared/plates.lua`
  and the `LABELS` map in `html/app.js`.
* Counter locations, key, and limits: `shared/config.lua`.

## Browser test harness

`/workspace/sod_lottery_test/lotto_test.html` (shipped separately as `sod_lottery_test.zip`) is a
single-file **test harness**. It needs no server and works from `file://`. It has Buy and Simulate
buttons and settings inputs, which the real resource deliberately doesn't have.
