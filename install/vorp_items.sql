-- VORP: register the ticket item (vorp_inventory `items` table).
-- Image: copy install/images/vorp/lottery_ticket.png to vorp_inventory/html/img/items/lottery_ticket.png
-- `limit` = 50: a player can carry a stack of up to 50 tickets.
-- Column sets differ slightly between VORP versions; adjust if your table has
-- extra NOT NULL columns (e.g. `weight`, `groupId`, `metadata`).
INSERT IGNORE INTO `items` (`item`, `label`, `limit`, `can_remove`, `type`, `usable`, `desc`)
VALUES ('lottery_ticket', 'Deliverance Fortune Ticket', 50, 1, 'item_standard', 1,
        'A scratch ticket of the State of Deliverance Territorial Lottery. Use it to scratch.');
