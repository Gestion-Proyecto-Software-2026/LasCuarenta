-- Nombre y contraseña opcional para las salas del lobby.
-- password_hash: bcrypt del SHA-256 que envía el cliente, igual que usuarios.password_hash.

ALTER TABLE salas
    ADD COLUMN nombre TEXT NOT NULL DEFAULT 'Sala de Guiñote',
    ADD COLUMN password_hash TEXT,
    ADD CONSTRAINT nombre_valido CHECK (char_length(nombre) BETWEEN 1 AND 40);
