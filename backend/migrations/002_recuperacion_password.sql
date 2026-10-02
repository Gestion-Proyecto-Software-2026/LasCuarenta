-- Códigos de un solo uso para recuperar contraseña por correo (PBI-01)
-- Ver docs/analisis_funcional_app.md §5 (Autenticación)

CREATE TABLE codigos_recuperacion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id UUID NOT NULL REFERENCES usuarios(id),
    codigo_hash TEXT NOT NULL,
    expira_en TIMESTAMPTZ NOT NULL,
    usado BOOLEAN NOT NULL DEFAULT false,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_codigos_recuperacion_usuario ON codigos_recuperacion(usuario_id);
