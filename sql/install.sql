-- TaxiJob – ESX Legacy Installation
-- Hinweis: Job "taxi" und society_taxi werden von esx_taxijob mitgeliefert.
-- Falls noch nicht vorhanden, einmalig die Datei aus esx_taxijob importieren:
--   resources/[esx_addons]/esx_taxijob/localization/de_esx_taxijob.sql

CREATE TABLE IF NOT EXISTS `taxijob_trips` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `driver_identifier` VARCHAR(60) NOT NULL,
    `driver_name` VARCHAR(64) NOT NULL,
    `passenger_identifier` VARCHAR(60) DEFAULT NULL,
    `passenger_name` VARCHAR(64) DEFAULT NULL,
    `distance_km` DECIMAL(10, 3) NOT NULL DEFAULT 0,
    `fare` DECIMAL(10, 2) NOT NULL DEFAULT 0,
    `tip` DECIMAL(10, 2) NOT NULL DEFAULT 0,
    `total` DECIMAL(10, 2) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_driver` (`driver_identifier`),
    KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
