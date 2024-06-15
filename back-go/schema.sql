DROP DATABASE IF EXISTS `eagle-fox`;
CREATE DATABASE IF NOT EXISTS `eagle-fox` DEFAULT CHARACTER SET utf8;
USE `eagle-fox`;

-- Tabla de usuarios
CREATE TABLE IF NOT EXISTS `user` (
    `id`               int                    NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `nombre`           varchar(255)           NOT NULL,
    `nombre_segundo`   varchar(255)                    DEFAULT NULL,
    `apellido_primero` varchar(255)           NOT NULL,
    `apellido_segundo` varchar(255)           NOT NULL,
    `email`            varchar(255)           NOT NULL UNIQUE,
    `password`         char(64)               NOT NULL,
    `rol`              enum ('ADMIN', 'USER') NOT NULL DEFAULT 'USER',
    `created_at`       datetime               NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`       datetime               NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `deleted_at`       datetime               DEFAULT NULL
) ENGINE = InnoDB;

-- Insertar usuario administrador
INSERT INTO `user` (`nombre`, `apellido_primero`, `apellido_segundo`, `email`, `password`, `rol`)
VALUES ('admin', 'admin', 'admin', 'admin@admin.com', SHA2('admin', 256), 'ADMIN');

-- Tabla de clientes
CREATE TABLE IF NOT EXISTS `clients` (
    `id`         int          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `ipv4`       char(15)     NOT NULL COMMENT 'IPv4 address',
    `token`      char(36)     NOT NULL COMMENT '128 bits UUID (RFC 4122)',
    `locked`     boolean      NOT NULL DEFAULT FALSE,
    `user`       int          NOT NULL,
    `created_at` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `deleted_at` datetime     DEFAULT NULL,
    FOREIGN KEY (`user`) REFERENCES `user` (`id`)
) ENGINE = InnoDB;

-- Vista de clientes
CREATE VIEW `v_clients` AS
SELECT `id`,
        INET_NTOA(`ipv4`) AS `ipv4`,
    `token`,
    `locked`,
    `user`,
    `created_at`,
    `updated_at`
FROM `clients`;

-- Tabla de registros de log
CREATE TABLE IF NOT EXISTS `log` (
    `id`         int          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `user`       int          NOT NULL,
    `client`     int          NOT NULL,
    `message`    varchar(255) NOT NULL COMMENT 'Principalmente para control de acceso (no necesariamente los de Apache)',
    `created_at` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `deleted_at` datetime     DEFAULT NULL,
    FOREIGN KEY (`user`) REFERENCES `user` (`id`),
    FOREIGN KEY (`client`) REFERENCES `clients` (`id`)
) ENGINE = InnoDB;

-- Vista de registros de log
CREATE VIEW `v_log` AS
SELECT `log`.`id`,
    `user`.`nombre`             AS `usuario`,
        INET_NTOA(`clients`.`ipv4`) AS `cliente`,
    `log`.`message`,
    `log`.`created_at`,
    `log`.`updated_at`
FROM `log`
         JOIN `user` ON `log`.`user` = `user`.`id`
         JOIN `clients` ON `log`.`client` = `clients`.`id`;

-- Tabla de dispositivos IoT
CREATE TABLE IF NOT EXISTS `iot_devices` (
    `id`             int          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `token`          CHAR(36)     NOT NULL UNIQUE COMMENT '128 bits UUID (RFC 4122)',
    `name`           varchar(255)          DEFAULT 'IoT',
    `especie`        varchar(255)          DEFAULT 'Mascota',
    `cumpleanos`     date                     DEFAULT NULL,
    `icon`           varchar(255) NOT NULL,
    `user`           int          NOT NULL,
    `last_latitude`  DECIMAL(10, 8)        DEFAULT NULL,
    `last_longitude` DECIMAL(11, 8)        DEFAULT NULL,
    `created_at`     datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`     datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `deleted_at`     datetime     DEFAULT NULL,
    INDEX `idx_token` (`token`) USING HASH COMMENT 'Sólo soporta igualdad',
    FOREIGN KEY (`user`) REFERENCES `user` (`id`)
) ENGINE = InnoDB;

-- Tabla de datos de IoT
CREATE TABLE IF NOT EXISTS `iot_data` (
    `id`         int            NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `device`     int            NOT NULL,
    `latitude`   DECIMAL(10, 8) NOT NULL,
    `longitude`  DECIMAL(11, 8) NOT NULL,
    `created_at` datetime       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` datetime       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `deleted_at` datetime       DEFAULT NULL,
    FOREIGN KEY (`device`) REFERENCES `iot_devices` (`id`)
) ENGINE = InnoDB;

-- Trigger para actualizar la última ubicación en dispositivos IoT
        DELIMITER //
CREATE TRIGGER update_last_location
    AFTER INSERT
              ON iot_data
                 FOR EACH ROW
BEGIN
    UPDATE iot_devices
    SET last_latitude  = NEW.latitude,
        last_longitude = NEW.longitude,
        updated_at     = NOW()
    WHERE id = NEW.device;
END;
//
DELIMITER ;

-- Evento para eliminar datos antiguos de IoT
        DELIMITER $$
CREATE EVENT IF NOT EXISTS `delete_old_iot_data`
    ON SCHEDULE EVERY 1 DAY
    DO
BEGIN
    DELETE FROM `iot_data` WHERE `created_at` < DATE_SUB(NOW(), INTERVAL 30 DAY);
            END$$
            DELIMITER ;

-- Evento para eliminar registros de log antiguos
            DELIMITER $$
    CREATE EVENT IF NOT EXISTS `delete_old_logs`
    ON SCHEDULE EVERY 1 HOUR
    DO
    BEGIN
        DECLARE `log_count` INT;
        SELECT COUNT(*) INTO `log_count` FROM `log`;
        IF `log_count` > 1024 THEN
        CREATE TEMPORARY TABLE `temp_log` AS
        SELECT `id` FROM `log` ORDER BY `created_at` LIMIT 512;

        DELETE FROM `log` WHERE `id` IN (SELECT `id` FROM `temp_log`);

        DROP TEMPORARY TABLE `temp_log`;
    END IF;
            END$$
            DELIMITER ;