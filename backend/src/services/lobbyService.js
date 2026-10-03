const pool = require("../models/db");
const { ErrorHttp } = require("../utils/errorHttp");

const JUEGOS = ["guinote", "mus", "tute"];
const JUEGOS_CREABLES = ["guinote"];
const CAPACIDAD_GUINOTE = 4;
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function validarJuego(juego, permitidos) {
  if (!permitidos.includes(juego)) {
    throw new ErrorHttp(
      400,
      `juego no válido, valores admitidos: ${permitidos.join(", ")}`,
    );
  }
}

async function listarSalas({ juego } = {}) {
  if (juego !== undefined) validarJuego(juego, JUEGOS);

  const { rows } = await pool.query(
    `SELECT s.id, s.juego, s.estado, s.capacidad, s.creador_id,
            COUNT(p.usuario_id)::int AS jugadores_actuales
     FROM salas s
     LEFT JOIN sala_participantes p ON p.sala_id = s.id
     WHERE s.estado = 'esperando' AND ($1::text IS NULL OR s.juego = $1)
     GROUP BY s.id
     HAVING COUNT(p.usuario_id) < s.capacidad
     ORDER BY s.fecha_creacion`,
    [juego ?? null],
  );
  return rows;
}

async function crearSala({ juego }, usuarioId) {
  validarJuego(juego, JUEGOS_CREABLES);

  const cliente = await pool.connect();
  try {
    await cliente.query("BEGIN");
    const { rows } = await cliente.query(
      `INSERT INTO salas (juego, capacidad, creador_id)
       VALUES ($1, $2, $3)
       RETURNING id, juego, estado, capacidad`,
      [juego, CAPACIDAD_GUINOTE, usuarioId],
    );
    const sala = rows[0];
    await cliente.query(
      "INSERT INTO sala_participantes (sala_id, usuario_id, posicion) VALUES ($1, $2, 0)",
      [sala.id, usuarioId],
    );
    await cliente.query("COMMIT");
    return {
      ...sala,
      servidor_direccion: process.env.GAME_SERVER_ADDRESS,
    };
  } catch (err) {
    await cliente.query("ROLLBACK");
    throw err;
  } finally {
    cliente.release();
  }
}

async function unirseSala(salaId, usuarioId) {
  if (typeof salaId !== "string" || !UUID_RE.test(salaId)) {
    throw new ErrorHttp(400, "id de sala no válido");
  }

  const cliente = await pool.connect();
  try {
    await cliente.query("BEGIN");

    const { rows: salas } = await cliente.query(
      `SELECT id, juego, estado, capacidad, creador_id
       FROM salas WHERE id = $1 FOR UPDATE`,
      [salaId],
    );
    const sala = salas[0];
    if (!sala) throw new ErrorHttp(404, "la sala no existe");
    if (sala.estado !== "esperando") {
      throw new ErrorHttp(409, "la sala no admite nuevos jugadores");
    }

    const { rows: participantes } = await cliente.query(
      "SELECT usuario_id, posicion FROM sala_participantes WHERE sala_id = $1",
      [salaId],
    );
    if (participantes.some((p) => p.usuario_id === usuarioId)) {
      throw new ErrorHttp(409, "ya estás en esta sala");
    }
    if (participantes.length >= sala.capacidad) {
      throw new ErrorHttp(409, "la sala está llena");
    }

    const ocupadas = new Set(participantes.map((p) => p.posicion));
    let posicion = 0;
    while (ocupadas.has(posicion)) posicion++;

    await cliente.query(
      "INSERT INTO sala_participantes (sala_id, usuario_id, posicion) VALUES ($1, $2, $3)",
      [salaId, usuarioId, posicion],
    );
    await cliente.query("COMMIT");

    return {
      id: sala.id,
      juego: sala.juego,
      estado: sala.estado,
      capacidad: sala.capacidad,
      creador_id: sala.creador_id,
      jugadores_actuales: participantes.length + 1,
    };
  } catch (err) {
    await cliente.query("ROLLBACK");
    throw err;
  } finally {
    cliente.release();
  }
}

module.exports = { listarSalas, crearSala, unirseSala };
