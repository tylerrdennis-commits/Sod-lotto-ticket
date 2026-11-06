-- State of Deliverance Territorial Lottery - install SQL (MySQL / MariaDB, oxmysql)
-- The resource also creates these automatically when Config.AutoCreateTables = true.

CREATE TABLE IF NOT EXISTS `sod_lottery_kv` (
  `k` VARCHAR(64) NOT NULL,
  `v` LONGTEXT NOT NULL,
  PRIMARY KEY (`k`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `sod_lottery_tickets` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(80) NOT NULL,
  `name` VARCHAR(100) NOT NULL DEFAULT '',
  `source_type` VARCHAR(10) NOT NULL DEFAULT 'direct',
  `price` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `house_cut` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `jackpot_cut` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `backing_cut` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `plate` VARCHAR(24) DEFAULT NULL,
  `payout` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_created` (`created_at`),
  KEY `idx_payout` (`payout`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `sod_lottery_entries` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `period` INT UNSIGNED NOT NULL,
  `identifier` VARCHAR(80) NOT NULL,
  `name` VARCHAR(100) NOT NULL DEFAULT '',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_period` (`period`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `sod_lottery_winners` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `kind` VARCHAR(12) NOT NULL,          -- instant | moonshine | jackpot | draw
  `identifier` VARCHAR(80) NOT NULL,
  `name` VARCHAR(100) NOT NULL DEFAULT '',
  `plate` VARCHAR(24) DEFAULT NULL,
  `amount` DECIMAL(12,2) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `sod_lottery_audit` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `action` VARCHAR(24) NOT NULL,        -- givemoney | takemoney
  `admin` VARCHAR(120) NOT NULL,
  `target` VARCHAR(120) NOT NULL,
  `amount` DECIMAL(12,2) NOT NULL,
  `before_cash` DECIMAL(14,2) NOT NULL,
  `after_cash` DECIMAL(14,2) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `sod_lottery_pending` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(80) NOT NULL,
  `amount` DECIMAL(12,2) NOT NULL,
  `reason` VARCHAR(40) NOT NULL DEFAULT '',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
