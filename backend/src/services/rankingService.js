const pool = require("../models/db");
const { ErrorHttp } = require("../utils/errorHttp");

const JUEGOS = ["guinote", "mus", "tute"];
const LIMITE_POR_DEFECTO = 100;
const LIMITE_MAXIMO = 500;

function validarJuego(juego) {
  if (!JUEGOS.includes(juego)) {
    throw new ErrorHttp(
      400,
      `juego no válido, valores admitidos: ${JUEGOS.join(", ")}`,
    );
  }
}

function validarLimite(limite) {
  if (limite === undefined) return LIMITE_POR_DEFECTO;
  const n = Number(limite);
  if (!Number.isInteger(n) || n < 1 || n > LIMITE_MAXIMO) {
    throw new ErrorHttp(
      400,
      `limite no válido (entero de 1 a ${LIMITE_MAXIMO})`,
    );
  }
  return n;
}

// GET /api/ranking?juego=guinote — PBI-07. No hay tabla propia: se agrega
// partida_jugadores (ver docs/analisis_funcional_app.md §4). Orden: puntos
// acumulados, y a igualdad, más partidas ganadas y luego nombre. `posicion`
// usa RANK() sobre los puntos, así que dos jugadores empatados a puntos
// comparten puesto (1, 2, 2, 4...).
async function obtenerRanking({ juego, limite } = {}) {
  if (juego !== undefined) validarJuego(juego);
  const filas = validarLimite(limite);

  const { rows } = await pool.query(
    `SELECT u.id AS usuario_id, u.nombre_visible,
            SUM(pj.puntos_obtenidos)::int AS puntos_totales,
            COUNT(*)::int AS partidas_jugadas,
            COUNT(*) FILTER (WHERE pj.gano)::int AS partidas_ganadas,
            RANK() OVER (ORDER BY SUM(pj.puntos_obtenidos) DESC)::int AS posicion
     FROM partida_jugadores pj
     JOIN partidas p ON p.id = pj.partida_id
     JOIN usuarios u ON u.id = pj.usuario_id
     WHERE ($1::text IS NULL OR p.juego = $1)
     GROUP BY u.id, u.nombre_visible
     ORDER BY puntos_totales DESC, partidas_ganadas DESC, u.nombre_visible ASC
     LIMIT $2`,
    [juego ?? null, filas],
  );
  return rows;
}

module.exports = { obtenerRanking };
