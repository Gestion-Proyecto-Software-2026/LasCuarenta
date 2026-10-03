-- Restricciones del lobby de salas (PBI-02). Ver docs/analisis_funcional_app.md §4-§5.
-- Las tablas ya existen desde 001_init.sql: aquí solo se endurece el esquema.

ALTER TABLE salas
    ADD CONSTRAINT capacidad_valida CHECK (capacidad BETWEEN 1 AND 4);

ALTER TABLE sala_participantes
    ADD CONSTRAINT posicion_valida CHECK (posicion BETWEEN 0 AND 3);

ALTER TABLE sala_participantes
    ADD CONSTRAINT posicion_unica UNIQUE (sala_id, posicion);

CREATE INDEX idx_salas_juego_estado ON salas(juego, estado);
