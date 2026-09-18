-- Esquema inicial — ver docs/analisis_funcional_app.md §4

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE usuarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    nombre_visible TEXT NOT NULL,
    fecha_registro TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE salas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    juego TEXT NOT NULL CHECK (juego IN ('guinote', 'mus', 'tute')),
    estado TEXT NOT NULL DEFAULT 'esperando' CHECK (estado IN ('esperando', 'en_curso', 'finalizada')),
    capacidad SMALLINT NOT NULL,
    creador_id UUID NOT NULL REFERENCES usuarios(id),
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sala_participantes (
    sala_id UUID NOT NULL REFERENCES salas(id),
    usuario_id UUID NOT NULL REFERENCES usuarios(id),
    posicion SMALLINT NOT NULL,
    equipo SMALLINT,
    PRIMARY KEY (sala_id, usuario_id)
);

CREATE TABLE partidas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sala_id UUID REFERENCES salas(id),
    juego TEXT NOT NULL,
    fecha_inicio TIMESTAMPTZ NOT NULL,
    fecha_fin TIMESTAMPTZ,
    resultado_json JSONB
);

CREATE TABLE partida_jugadores (
    partida_id UUID NOT NULL REFERENCES partidas(id),
    usuario_id UUID NOT NULL REFERENCES usuarios(id),
    equipo SMALLINT,
    puntos_obtenidos INTEGER NOT NULL DEFAULT 0,
    gano BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (partida_id, usuario_id)
);
