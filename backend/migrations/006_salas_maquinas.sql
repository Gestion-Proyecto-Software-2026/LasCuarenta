-- Jugadores máquina en las salas (PBI-20). Ver docs/analisis_funcional_app.md §4-§5.
--
-- Una plaza de una sala la ocupa una persona (sala_participantes) o una máquina
-- (esta tabla). Que la posición no se repita entre las dos tablas lo garantiza el
-- backend dentro de una transacción con la fila de la sala bloqueada (FOR UPDATE);
-- aquí solo se evita repetirla entre máquinas. Si la sala se borra, sus máquinas
-- también.

CREATE TABLE sala_maquinas (
    sala_id UUID NOT NULL REFERENCES salas(id) ON DELETE CASCADE,
    posicion SMALLINT NOT NULL CHECK (posicion BETWEEN 0 AND 3),
    dificultad TEXT NOT NULL CHECK (dificultad IN ('facil', 'normal', 'dificil')),
    PRIMARY KEY (sala_id, posicion)
);
