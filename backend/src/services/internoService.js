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
    "SELECT id, juego, estado, capacidad FROM salas WHERE id = $1",
    [salaId],
  );
  const sala = salas[0];
  if (!sala) throw new ErrorHttp(404, "la sala no existe");

  const { rows: participantes } = await pool.query(
    "SELECT usuario_id, posicion FROM sala_participantes WHERE sala_id = $1 ORDER BY posicion",
    [salaId],
  );

  return {
    ...sala,
    participantes: participantes.map((p) => ({
      usuario_id: p.usuario_id,
      posicion: p.posicion,
      equipo: equipoDe(p.posicion),
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

module.exports = { obtenerSala, registrarPartida };
