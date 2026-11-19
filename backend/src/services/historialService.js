const pool = require("../models/db");
const { ErrorHttp } = require("../utils/errorHttp");

// Mismo orden en que se devuelven en estadisticas.por_juego.
const JUEGOS = ["guinote", "mus", "tute"];
const LIMITE_POR_DEFECTO = 100;
const LIMITE_MAXIMO = 500;
const ULTIMOS_RESULTADOS = 10;
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// `me` es un alias del usuario del token, para que el cliente no tenga que
// guardar su propio id solo para pedir su historial.
function resolverUsuario(id, solicitanteId) {
  if (id === "me") return solicitanteId;
  if (typeof id !== "string" || !UUID_RE.test(id)) {
    throw new ErrorHttp(400, "id de usuario no válido");
  }
  return id;
}

// Un parámetro de consulta vacío (`?juego=`) cuenta como no enviado.
function sinValor(valor) {
  return valor === undefined || valor === "";
}

function validarJuego(juego) {
  if (sinValor(juego)) return null;
  if (!JUEGOS.includes(juego)) {
    throw new ErrorHttp(
      400,
      `juego no válido, valores admitidos: ${JUEGOS.join(", ")}`,
    );
  }
  return juego;
}

function validarLimite(limite) {
  if (sinValor(limite)) return LIMITE_POR_DEFECTO;
  const numero =
    typeof limite === "string" && /^\d+$/.test(limite) ? Number(limite) : NaN;
  if (!(numero >= 1 && numero <= LIMITE_MAXIMO)) {
    throw new ErrorHttp(400, "limite no válido (entero de 1 a 500)");
  }
  return numero;
}

// Común a historial y estadísticas: el titular siempre ve lo suyo; los demás,
// solo si lo tiene público (HU-037, CA-137/138).
async function comprobarAcceso(usuarioId, solicitanteId) {
  const { rows } = await pool.query(
    "SELECT id, nombre_visible, historial_publico FROM usuarios WHERE id = $1",
    [usuarioId],
  );
  const usuario = rows[0];
  if (!usuario) throw new ErrorHttp(404, "el usuario no existe");
  const esTitular =
    String(usuario.id).toLowerCase() === String(solicitanteId).toLowerCase();
  if (!esTitular && !usuario.historial_publico) {
    throw new ErrorHttp(403, "este historial es privado");
  }
  return usuario;
}

function porPosicion(a, b) {
  return (a.posicion ?? Infinity) - (b.posicion ?? Infinity);
}

function sinEquipo({ usuario_id, nombre_visible, posicion }) {
  return { usuario_id, nombre_visible, posicion };
}

// Una fila de la consulta del historial → Partida del contrato (§5). `otros` son
// los demás jugadores de la partida; aquí se reparten en compañeros y rivales.
function formatearPartida(fila) {
  const otros = [...(fila.otros || [])].sort(porPosicion);
  return {
    partida_id: fila.partida_id,
    sala_id: fila.sala_id,
    juego: fila.juego,
    num_jugadores: fila.num_jugadores,
    fecha_inicio: fila.fecha_inicio,
    fecha_fin: fila.fecha_fin,
    resultado: fila.gano ? "victoria" : "derrota",
    gano: fila.gano,
    causa: fila.causa,
    // Guiñote y Tute: tute, tantos, vuelta o capote. El Mus no lo tiene.
    motivo: fila.motivo ?? null,
    equipo: fila.equipo,
    puntos_equipo: fila.puntos_equipo,
    puntos_rival: fila.puntos_rival,
    companeros: otros.filter((o) => o.equipo === fila.equipo).map(sinEquipo),
    rivales: otros.filter((o) => o.equipo !== fila.equipo).map(sinEquipo),
  };
}

// GET /api/usuarios/:id/historial — partidas terminadas, de la más reciente a la
// más antigua (PBI-06). puntos_rival es lo de cualquier jugador del otro equipo:
// todos los de un equipo tienen los mismos puntos_obtenidos.
async function listarHistorial(id, solicitanteId, { juego, limite } = {}) {
  const usuarioId = resolverUsuario(id, solicitanteId);
  const filtroJuego = validarJuego(juego);
  const maximo = validarLimite(limite);
  await comprobarAcceso(usuarioId, solicitanteId);

  const { rows } = await pool.query(
    `SELECT p.id AS partida_id, p.sala_id, p.juego, p.fecha_inicio, p.fecha_fin, p.causa,
            p.resultado_json->>'motivo' AS motivo,
            yo.equipo, yo.gano, yo.puntos_obtenidos AS puntos_equipo,
            COALESCE(MAX(o.puntos_obtenidos) FILTER (WHERE o.equipo IS DISTINCT FROM yo.equipo), 0)::int AS puntos_rival,
            COUNT(o.usuario_id)::int AS num_jugadores,
            COALESCE(
              json_agg(
                json_build_object(
                  'usuario_id', o.usuario_id,
                  'nombre_visible', u.nombre_visible,
                  'posicion', o.posicion,
                  'equipo', o.equipo
                ) ORDER BY o.posicion
              ) FILTER (WHERE o.usuario_id <> yo.usuario_id),
              '[]'
            ) AS otros
     FROM partida_jugadores yo
     JOIN partidas p ON p.id = yo.partida_id
     JOIN partida_jugadores o ON o.partida_id = p.id
     JOIN usuarios u ON u.id = o.usuario_id
     WHERE yo.usuario_id = $1 AND ($2::text IS NULL OR p.juego = $2)
     GROUP BY p.id, yo.usuario_id, yo.equipo, yo.gano, yo.puntos_obtenidos
     ORDER BY p.fecha_fin DESC NULLS LAST, p.id DESC
     LIMIT $3`,
    [usuarioId, filtroJuego, maximo],
  );
  return rows.map(formatearPartida);
}

function resultadoDe(fila) {
  return fila.gano ? "victoria" : "derrota";
}

// Porcentaje con 1 decimal (58.3); 0 si no hay partidas.
function porcentajeVictorias(victorias, jugadas) {
  if (jugadas === 0) return 0;
  return Math.round((victorias / jugadas) * 1000) / 10;
}

function resumir(filas) {
  const jugadas = filas.length;
  const victorias = filas.filter((f) => f.gano).length;
  return {
    jugadas,
    victorias,
    derrotas: jugadas - victorias,
    porcentaje_victorias: porcentajeVictorias(victorias, jugadas),
  };
}

// Resultados consecutivos iguales empezando por el más reciente (el primero).
function rachaActual(resultados) {
  if (resultados.length === 0) return { tipo: null, partidas: 0 };
  const tipo = resultados[0];
  let partidas = 0;
  while (partidas < resultados.length && resultados[partidas] === tipo) {
    partidas++;
  }
  return { tipo, partidas };
}

// La serie más larga de victorias seguidas. Da igual recorrerlas de la más
// reciente a la más antigua o al revés: la longitud de cada serie es la misma.
function mejorRachaVictorias(resultados) {
  let mejor = 0;
  let actual = 0;
  for (const resultado of resultados) {
    actual = resultado === "victoria" ? actual + 1 : 0;
    mejor = Math.max(mejor, actual);
  }
  return mejor;
}

// Lógica pura de GET /usuarios/:id/estadisticas, sin base de datos: recibe
// [{ juego, gano }] de la más reciente a la más antigua.
function calcularEstadisticas(filas) {
  const resultados = filas.map(resultadoDe);
  return {
    totales: resumir(filas),
    // Siempre los tres juegos y en el mismo orden, aunque sea con ceros, para
    // que el cliente no tenga que rellenar huecos.
    por_juego: JUEGOS.map((juego) => ({
      juego,
      ...resumir(filas.filter((f) => f.juego === juego)),
    })),
    racha_actual: rachaActual(resultados),
    mejor_racha_victorias: mejorRachaVictorias(resultados),
    ultimos_resultados: resultados.slice(0, ULTIMOS_RESULTADOS),
  };
}

// GET /api/usuarios/:id/estadisticas — totales, por juego, rachas y últimos
// resultados (PBI-06). Mismo control de acceso que el historial.
async function obtenerEstadisticas(id, solicitanteId) {
  const usuarioId = resolverUsuario(id, solicitanteId);
  const usuario = await comprobarAcceso(usuarioId, solicitanteId);

  const { rows } = await pool.query(
    `SELECT p.juego, pj.gano
     FROM partida_jugadores pj
     JOIN partidas p ON p.id = pj.partida_id
     WHERE pj.usuario_id = $1
     ORDER BY p.fecha_fin DESC NULLS LAST, p.id DESC`,
    [usuarioId],
  );
  return {
    usuario_id: usuario.id,
    nombre_visible: usuario.nombre_visible,
    historial_publico: usuario.historial_publico,
    ...calcularEstadisticas(rows),
  };
}

// GET /api/usuarios/me/privacidad
async function obtenerPrivacidad(usuarioId) {
  const { rows } = await pool.query(
    "SELECT historial_publico FROM usuarios WHERE id = $1",
    [usuarioId],
  );
  if (!rows[0]) throw new ErrorHttp(404, "el usuario no existe");
  return { historial_publico: rows[0].historial_publico };
}

// PUT /api/usuarios/me/privacidad — solo el titular decide si su historial es
// público (HU-037, CA-137).
async function cambiarPrivacidad(usuarioId, { historial_publico } = {}) {
  if (typeof historial_publico !== "boolean") {
    throw new ErrorHttp(400, "historial_publico tiene que ser true o false");
  }
  const { rows } = await pool.query(
    "UPDATE usuarios SET historial_publico = $2 WHERE id = $1 RETURNING historial_publico",
    [usuarioId, historial_publico],
  );
  if (!rows[0]) throw new ErrorHttp(404, "el usuario no existe");
  return { historial_publico: rows[0].historial_publico };
}

module.exports = {
  listarHistorial,
  obtenerEstadisticas,
  obtenerPrivacidad,
  cambiarPrivacidad,
  // Lógica pura, exportada para probarla sin base de datos.
  formatearPartida,
  calcularEstadisticas,
  rachaActual,
  mejorRachaVictorias,
  porcentajeVictorias,
};
