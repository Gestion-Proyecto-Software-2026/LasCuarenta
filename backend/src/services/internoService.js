const pool = require("../models/db");
const { ErrorHttp } = require("../utils/errorHttp");

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Fecha y hora ISO 8601 con zona (Z o ±hh:mm), como las que manda el servidor
// de partida. Sin zona, Node y PostgreSQL podrían interpretarla en husos distintos.
const FECHA_ISO_RE =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/i;

// Por qué terminó la partida (partidas.causa). La lista vive aquí y no en un
// CHECK de la base de datos: la derrota por desconexión (HU-013) añadirá
// "desconexion" sin necesitar una migración.
const CAUSAS = ["completa", "renuncio"];
const CAUSA_POR_DEFECTO = "completa";

// Índice único de 005_historial_estadisticas.sql: una sala, una partida.
const INDICE_SALA_UNICA = "partidas_sala_unica";
const ERROR_YA_REGISTRADA = "la partida de esta sala ya está registrada";

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

function esEnteroEntre(valor, minimo, maximo) {
  return Number.isInteger(valor) && valor >= minimo && valor <= maximo;
}

function validarJugadores(jugadores) {
  if (!Array.isArray(jugadores) || jugadores.length === 0) {
    throw new ErrorHttp(400, "jugadores debe ser un array no vacío");
  }
  const usuarios = new Set();
  const posiciones = new Set();
  for (const j of jugadores) {
    if (!j || typeof j !== "object") {
      throw new ErrorHttp(
        400,
        "cada jugador necesita usuario_id, posicion y equipo",
      );
    }
    // Un usuario_id vacío (asiento sin nadie) llegaba hasta PostgreSQL y
    // acababa en un 500; ahora se rechaza aquí, sin tocar la base de datos.
    if (typeof j.usuario_id !== "string" || !UUID_RE.test(j.usuario_id)) {
      throw new ErrorHttp(400, "usuario_id de jugador no válido");
    }
    if (!esEnteroEntre(j.posicion, 0, 3)) {
      throw new ErrorHttp(
        400,
        "posicion de jugador no válida (entero de 0 a 3)",
      );
    }
    if (!esEnteroEntre(j.equipo, 0, 1)) {
      throw new ErrorHttp(400, "equipo de jugador no válido (0 o 1)");
    }
    // Repetido chocaría con la clave primaria de partida_jugadores, y ese
    // 23505 no se debe confundir con el de una partida ya registrada.
    const usuario = j.usuario_id.toLowerCase();
    if (usuarios.has(usuario)) {
      throw new ErrorHttp(400, "un jugador aparece más de una vez");
    }
    if (posiciones.has(j.posicion)) {
      throw new ErrorHttp(400, "dos jugadores en la misma posicion");
    }
    usuarios.add(usuario);
    posiciones.add(j.posicion);
  }
}

function validarResultado(resultado) {
  if (!resultado || typeof resultado !== "object" || Array.isArray(resultado)) {
    throw new ErrorHttp(400, "resultado es obligatorio");
  }
  if (!esEnteroEntre(resultado.equipo_ganador, 0, 1)) {
    throw new ErrorHttp(400, "resultado.equipo_ganador tiene que ser 0 o 1");
  }
  const puntos = resultado.puntos_por_equipo;
  if (
    puntos !== undefined &&
    (!Array.isArray(puntos) ||
      puntos.length !== 2 ||
      !puntos.every((p) => Number.isInteger(p) && p >= 0))
  ) {
    throw new ErrorHttp(
      400,
      "resultado.puntos_por_equipo tiene que ser un array de 2 enteros no negativos",
    );
  }
  if (resultado.causa !== undefined && !CAUSAS.includes(resultado.causa)) {
    throw new ErrorHttp(
      400,
      `resultado.causa no válida, valores admitidos: ${CAUSAS.join(", ")}`,
    );
  }
  if (tieneTextoNoGuardable(resultado)) {
    throw new ErrorHttp(
      400,
      "resultado contiene caracteres que no se pueden guardar (\\u0000 o UTF-16 mal formado)",
    );
  }
}

// JSONB no admite el carácter nulo (\u0000) ni un sustituto UTF-16 suelto, en
// ningún texto ni en ninguna clave: PostgreSQL lo rechazaría (22P05, 22P02) con
// un 500 que el servidor de partida reintentaría en vano. Se mira aquí, con el resto.
function tieneTextoNoGuardable(valor) {
  if (typeof valor === "string") {
    return valor.includes("\u0000") || !valor.isWellFormed();
  }
  if (valor !== null && typeof valor === "object") {
    return Object.entries(valor).some(
      ([clave, v]) => tieneTextoNoGuardable(clave) || tieneTextoNoGuardable(v),
    );
  }
  return false;
}

// Devuelve la fecha normalizada (ISO en UTC) o null si no viene.
function validarFecha(valor, campo) {
  if (valor === undefined || valor === null) return null;
  const ms = typeof valor === "string" ? Date.parse(valor) : NaN;
  if (Number.isNaN(ms) || !FECHA_ISO_RE.test(valor)) {
    throw new ErrorHttp(
      400,
      `${campo} no válida (se espera una fecha ISO 8601 con zona horaria)`,
    );
  }
  // Ya en UTC, el año puede salirse de 1-9999 (p. ej. "9999-12-31T23:00:00-05:00"
  // pasa al año 10000), y PostgreSQL no tiene año 0 ni lee los de más de 4 cifras
  // que escribe toISOString: sería un 500 que el servidor de partida reintentaría.
  const anio = new Date(ms).getUTCFullYear();
  if (anio < 1 || anio > 9999) {
    throw new ErrorHttp(
      400,
      `${campo} fuera de rango (el año, en UTC, tiene que ir de 1 a 9999)`,
    );
  }
  return new Date(ms).toISOString();
}

// Valida todo el body antes de abrir la transacción: un 400 nunca toca la base de datos.
function validarResultadoPartida(body) {
  const { sala_id, jugadores, resultado } = body;
  if (typeof sala_id !== "string" || !UUID_RE.test(sala_id)) {
    throw new ErrorHttp(400, "sala_id no válido");
  }
  validarJugadores(jugadores);
  validarResultado(resultado);
  const fechaInicio = validarFecha(body.fecha_inicio, "fecha_inicio");
  const fechaFin = validarFecha(body.fecha_fin, "fecha_fin");
  if (fechaInicio && fechaFin && new Date(fechaInicio) > new Date(fechaFin)) {
    throw new ErrorHttp(400, "fecha_inicio no puede ser posterior a fecha_fin");
  }
  return {
    fechaInicio,
    fechaFin,
    causa: resultado.causa ?? CAUSA_POR_DEFECTO,
  };
}

// POST /api/interno/partidas — persiste el resultado final y cierra la sala.
// Es idempotente: el servidor de partida reintenta si no le llega respuesta, así
// que una segunda llamada para la misma sala responde 409 sin duplicar nada.
async function registrarPartida(body) {
  const { fechaInicio, fechaFin, causa } = validarResultadoPartida(body);
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

    // Con la sala bloqueada, dos registros simultáneos van uno detrás de otro:
    // el segundo ya ve la partida del primero.
    const { rows: previas } = await cliente.query(
      "SELECT id FROM partidas WHERE sala_id = $1",
      [sala_id],
    );
    if (previas.length > 0) throw new ErrorHttp(409, ERROR_YA_REGISTRADA);

    // Sin fecha_fin, la de ahora; sin fecha_inicio, la misma que la de fin.
    const { rows: partidas } = await cliente.query(
      `INSERT INTO partidas (sala_id, juego, fecha_inicio, fecha_fin, resultado_json, causa)
       VALUES ($1, $2, COALESCE($3::timestamptz, $4::timestamptz, now()),
               COALESCE($4::timestamptz, now()), $5, $6)
       RETURNING id`,
      [
        sala_id,
        sala.juego,
        fechaInicio,
        fechaFin,
        JSON.stringify(resultado),
        causa,
      ],
    );
    const partidaId = partidas[0].id;

    const puntosPorEquipo = resultado.puntos_por_equipo || [];
    for (const jugador of jugadores) {
      const gano = jugador.equipo === resultado.equipo_ganador;
      const puntos = puntosPorEquipo[jugador.equipo] ?? 0;
      await cliente.query(
        `INSERT INTO partida_jugadores (partida_id, usuario_id, equipo, posicion, puntos_obtenidos, gano)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          partidaId,
          jugador.usuario_id,
          jugador.equipo,
          jugador.posicion,
          puntos,
          gano,
        ],
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
    throw traducirErrorBd(err);
  } finally {
    cliente.release();
  }
}

// Errores de PostgreSQL que son culpa del body y no del backend: así el
// servidor de partida no reintenta algo que nunca va a salir bien (reintenta
// solo ante 0 o 5xx, ver room_manager.gd).
function traducirErrorBd(err) {
  // Si a pesar del SELECT se cuela un duplicado, lo para el índice único.
  if (err.code === "23505" && err.constraint === INDICE_SALA_UNICA) {
    return new ErrorHttp(409, ERROR_YA_REGISTRADA);
  }
  // Clave foránea: algún usuario_id no corresponde a ninguna cuenta.
  if (err.code === "23503") {
    return new ErrorHttp(400, "algún jugador no existe");
  }
  return err;
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
