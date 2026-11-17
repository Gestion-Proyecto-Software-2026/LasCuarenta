const pool = require("../models/db");
const { ErrorHttp } = require("../utils/errorHttp");

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function equipoDe(posicion) {
  return posicion % 2;
}

// GET /api/interno/salas/:id — composición de una sala, para que el servidor de
// partida valide participantes antes de iniciar (ver docs/mapa/backend.md).
async function obtenerSala(salaId) {
  if (typeof salaId !== "string" || !UUID_RE.test(salaId)) {
    throw new ErrorHttp(400, "id de sala no válido");
  }

  const { rows: salas } = await pool.query(
    "SELECT id, juego, estado, capacidad, creador_id FROM salas WHERE id = $1",
    [salaId],
  );
  const sala = salas[0];
  if (!sala) throw new ErrorHttp(404, "la sala no existe");

  const { rows: participantes } = await pool.query(
    `SELECT p.usuario_id, p.posicion, u.nombre_visible
       FROM sala_participantes p
       JOIN usuarios u ON u.id = p.usuario_id
      WHERE p.sala_id = $1
      ORDER BY p.posicion`,
    [salaId],
  );

  return {
    ...sala,
    participantes: participantes.map((p) => ({
      usuario_id: p.usuario_id,
      posicion: p.posicion,
      equipo: equipoDe(p.posicion),
      // Para que el servidor de partida rotule la mesa con el nombre de cada uno.
      nombre_visible: p.nombre_visible,
    })),
  };
}

function validarResultadoPartida({ sala_id, jugadores, resultado }) {
  if (typeof sala_id !== "string" || !UUID_RE.test(sala_id)) {
    throw new ErrorHttp(400, "sala_id no válido");
  }
  if (!Array.isArray(jugadores) || jugadores.length === 0) {
    throw new ErrorHttp(400, "jugadores debe ser un array no vacío");
  }
  for (const j of jugadores) {
    if (
      typeof j.usuario_id !== "string" ||
      !Number.isInteger(j.posicion) ||
      !Number.isInteger(j.equipo)
    ) {
      throw new ErrorHttp(
        400,
        "cada jugador necesita usuario_id, posicion y equipo",
      );
    }
  }
  if (!resultado || typeof resultado !== "object") {
    throw new ErrorHttp(400, "resultado es obligatorio");
  }
  if (!Number.isInteger(resultado.equipo_ganador)) {
    throw new ErrorHttp(400, "resultado.equipo_ganador es obligatorio");
  }
}

// POST /api/interno/partidas — persiste el resultado final y cierra la sala.
async function registrarPartida(body) {
  validarResultadoPartida(body);
  const { sala_id, jugadores, resultado } = body;

  const cliente = await pool.connect();
  try {
    await cliente.query("BEGIN");

    const { rows: salas } = await cliente.query(
      "SELECT id, juego FROM salas WHERE id = $1 FOR UPDATE",
      [sala_id],
    );
    const sala = salas[0];
    if (!sala) throw new ErrorHttp(404, "la sala no existe");

    const { rows: partidas } = await cliente.query(
      `INSERT INTO partidas (sala_id, juego, fecha_inicio, fecha_fin, resultado_json)
       VALUES ($1, $2, now(), now(), $3)
       RETURNING id`,
      [sala_id, sala.juego, JSON.stringify(resultado)],
    );
    const partidaId = partidas[0].id;

    const puntosPorEquipo = resultado.puntos_por_equipo || [];
    for (const jugador of jugadores) {
      const gano = jugador.equipo === resultado.equipo_ganador;
      const puntos = puntosPorEquipo[jugador.equipo] ?? 0;
      await cliente.query(
        `INSERT INTO partida_jugadores (partida_id, usuario_id, equipo, puntos_obtenidos, gano)
         VALUES ($1, $2, $3, $4, $5)`,
        [partidaId, jugador.usuario_id, jugador.equipo, puntos, gano],
      );
    }

    await cliente.query(
      "UPDATE salas SET estado = 'finalizada' WHERE id = $1",
      [sala_id],
    );

    await cliente.query("COMMIT");
    return { id: partidaId };
  } catch (err) {
    await cliente.query("ROLLBACK");
    throw err;
  } finally {
    cliente.release();
  }
}

// POST /api/interno/salas/:id/iniciar — el servidor de partida avisa de que la
// partida ha empezado (el creador pulsó EMPEZAR): la sala pasa a `en_curso` y
// desde entonces ya no se puede expulsar, unirse ni abandonar (PBI-09).
// Idempotente: si ya estaba en curso no hace nada.
async function iniciarSala(salaId) {
  if (typeof salaId !== "string" || !UUID_RE.test(salaId)) {
    throw new ErrorHttp(400, "id de sala no válido");
  }
  const { rows } = await pool.query("SELECT estado FROM salas WHERE id = $1", [
    salaId,
  ]);
  if (!rows[0]) throw new ErrorHttp(404, "la sala no existe");
  if (rows[0].estado === "finalizada") {
    throw new ErrorHttp(409, "la sala ya ha terminado");
  }
  await pool.query(
    "UPDATE salas SET estado = 'en_curso' WHERE id = $1 AND estado = 'esperando'",
    [salaId],
  );
}

module.exports = { obtenerSala, registrarPartida, iniciarSala };
