-- Historial y estadísticas (PBI-06). Ver docs/analisis_funcional_app.md §4-§5.
-- Historial público por defecto: el titular puede hacerlo privado (PUT /usuarios/me/privacidad).
ALTER TABLE usuarios
    ADD COLUMN historial_publico BOOLEAN NOT NULL DEFAULT true;

-- Por qué terminó la partida: 'completa' (se jugó hasta el final) o 'renuncio'
-- (renuncio admitido en el chat, PBI-08). La lista válida la mantiene el backend.
ALTER TABLE partidas
    ADD COLUMN causa TEXT NOT NULL DEFAULT 'completa';

-- Asiento de cada jugador en la mesa, para listar compañero y rivales en orden.
ALTER TABLE partida_jugadores
    ADD COLUMN posicion SMALLINT;

-- Una sala aloja una sola partida: si el servidor de partida reintenta el
-- registro (POST /interno/partidas), no se duplica.
CREATE UNIQUE INDEX partidas_sala_unica ON partidas(sala_id);

CREATE INDEX idx_partida_jugadores_usuario ON partida_jugadores(usuario_id);
CREATE INDEX idx_partidas_fecha_fin ON partidas(fecha_fin DESC);
