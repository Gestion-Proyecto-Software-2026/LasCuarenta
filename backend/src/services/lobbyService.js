const bcrypt = require("bcrypt");
const pool = require("../models/db");
const { ErrorHttp } = require("../utils/errorHttp");

const JUEGOS = ["guinote", "mus", "tute"];
const JUEGOS_CREABLES = ["guinote", "mus", "tute"];
// Capacidades admitidas por juego: duplica a propósito lo que ya expresa
// jugadores_admitidos() en el motor Godot de cada juego (game/server/game_engine/*/motor_*.gd).
// Node no puede leer ese .gd, así que no hay una única fuente de verdad posible
// entre los dos stacks; si se cambia una, hay que recordar cambiar la otra.
const CAPACIDADES_POR_JUEGO = { guinote: [2, 4], mus: [2, 4], tute: [2, 4] };
const CAPACIDAD_POR_DEFECTO = 4;
const NOMBRE_POR_DEFECTO = "Sala de Guiñote";
const HASH_RE = /^[a-f0-9]{64}$/i;
const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS || 10);
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

function validarCapacidad(juego, capacidad) {
  const admitidas = CAPACIDADES_POR_JUEGO[juego];
  if (!admitidas.includes(capacidad)) {
    throw new ErrorHttp(
      400,
      `capacidad no válida para ${juego}, valores admitidos: ${admitidas.join(", ")}`,
    );
  }
}

function validarNombre(nombre) {
  if (typeof nombre !== "string" || nombre.length < 1 || nombre.length > 40) {
    throw new ErrorHttp(400, "nombre de sala no válido (1 a 40 caracteres)");
  }
}

// El cliente nunca manda la contraseña de la sala en claro: envía su SHA-256
// en hex (64 caracteres), igual que con la contraseña de la cuenta (ver
// authService.js); el backend aplica bcrypt antes de guardarla.
function validarPasswordHash(hash) {
  if (typeof hash !== "string" || !HASH_RE.test(hash)) {
    throw new ErrorHttp(
      400,
      "password_hash inválido: se espera SHA-256 en hexadecimal",
    );
  }
}

async function listarSalas({ juego } = {}) {
  if (juego !== undefined) validarJuego(juego, JUEGOS);

  const { rows } = await pool.query(
    `SELECT s.id, s.juego, s.estado, s.capacidad, s.creador_id, s.nombre,
            (s.password_hash IS NOT NULL) AS tiene_contrasena,
            COUNT(p.usuario_id)::int AS jugadores_actuales,
            COALESCE(
              json_agg(
                json_build_object(
                  'usuario_id', p.usuario_id,
                  'nombre_visible', u.nombre_visible,
                  'posicion', p.posicion
                ) ORDER BY p.posicion
              ) FILTER (WHERE p.usuario_id IS NOT NULL),
              '[]'
            ) AS jugadores
     FROM salas s
     LEFT JOIN sala_participantes p ON p.sala_id = s.id
     LEFT JOIN usuarios u ON u.id = p.usuario_id
     WHERE s.estado = 'esperando' AND ($1::text IS NULL OR s.juego = $1)
     GROUP BY s.id
     HAVING COUNT(p.usuario_id) < s.capacidad
     ORDER BY s.fecha_creacion`,
    [juego ?? null],
  );
  return rows;
}

async function crearSala(
  { juego, capacidad, nombre, password_hash },
  usuarioId,
) {
  validarJuego(juego, JUEGOS_CREABLES);
  const cap = capacidad === undefined ? CAPACIDAD_POR_DEFECTO : capacidad;
  validarCapacidad(juego, cap);
  const nombreSala = nombre === undefined ? NOMBRE_POR_DEFECTO : nombre;
  validarNombre(nombreSala);
  let hashAlmacenado = null;
  if (password_hash !== undefined) {
    validarPasswordHash(password_hash);
    hashAlmacenado = await bcrypt.hash(password_hash, SALT_ROUNDS);
  }

  const cliente = await pool.connect();
  try {
    await cliente.query("BEGIN");
    const { rows } = await cliente.query(
      `INSERT INTO salas (juego, capacidad, creador_id, nombre, password_hash)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, juego, estado, capacidad, nombre`,
      [juego, cap, usuarioId, nombreSala, hashAlmacenado],
    );
    const sala = rows[0];
    await cliente.query(
      "INSERT INTO sala_participantes (sala_id, usuario_id, posicion) VALUES ($1, $2, 0)",
      [sala.id, usuarioId],
    );
    await cliente.query("COMMIT");
    return {
      ...sala,
      tiene_contrasena: hashAlmacenado != null,
      servidor_direccion: process.env.GAME_SERVER_ADDRESS,
    };
  } catch (err) {
    await cliente.query("ROLLBACK");
    throw err;
  } finally {
    cliente.release();
  }
}

async function unirseSala(salaId, usuarioId, password_hash) {
  if (typeof salaId !== "string" || !UUID_RE.test(salaId)) {
    throw new ErrorHttp(400, "id de sala no válido");
  }

  const cliente = await pool.connect();
  try {
    await cliente.query("BEGIN");

    const { rows: salas } = await cliente.query(
      `SELECT id, juego, estado, capacidad, creador_id, password_hash
       FROM salas WHERE id = $1 FOR UPDATE`,
      [salaId],
    );
    const sala = salas[0];
    if (!sala) throw new ErrorHttp(404, "la sala no existe");
    if (sala.estado !== "esperando") {
      throw new ErrorHttp(409, "la sala no admite nuevos jugadores");
    }
    if (sala.password_hash) {
      const coincide =
        typeof password_hash === "string" &&
        (await bcrypt.compare(password_hash, sala.password_hash));
      if (!coincide) {
        throw new ErrorHttp(403, "contraseña incorrecta");
      }
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
      servidor_direccion: process.env.GAME_SERVER_ADDRESS,
    };
  } catch (err) {
    await cliente.query("ROLLBACK");
    throw err;
  } finally {
    cliente.release();
  }
}

// Abandonar una sala en espera (pantalla de espera, PBI-03). Si al salir no
// queda nadie, la sala se borra entera: evita salas fantasma abandonadas.
async function salirSala(salaId, usuarioId) {
  if (typeof salaId !== "string" || !UUID_RE.test(salaId)) {
    throw new ErrorHttp(400, "id de sala no válido");
  }

  const cliente = await pool.connect();
  try {
    await cliente.query("BEGIN");

    const { rows: salas } = await cliente.query(
      "SELECT id, estado, creador_id FROM salas WHERE id = $1 FOR UPDATE",
      [salaId],
    );
    const sala = salas[0];
    if (!sala) throw new ErrorHttp(404, "la sala no existe");
    if (sala.estado !== "esperando") {
      throw new ErrorHttp(409, "la sala no admite esta acción");
    }

    const { rowCount } = await cliente.query(
      "DELETE FROM sala_participantes WHERE sala_id = $1 AND usuario_id = $2",
      [salaId, usuarioId],
    );
    if (rowCount === 0) {
      throw new ErrorHttp(404, "no formas parte de esta sala");
    }

    const { rows: restantes } = await cliente.query(
      "SELECT COUNT(*)::int AS total FROM sala_participantes WHERE sala_id = $1",
      [salaId],
    );
    if (restantes[0].total === 0) {
      await cliente.query("DELETE FROM salas WHERE id = $1", [salaId]);
    } else if (sala.creador_id === usuarioId) {
      // Si se va el creador, la sala pasa al siguiente sentado (posición más
      // baja): sin creador nadie podría expulsar ni empezar la partida (PBI-09).
      await cliente.query(
        `UPDATE salas SET creador_id = (
           SELECT usuario_id FROM sala_participantes
            WHERE sala_id = $1 ORDER BY posicion LIMIT 1)
         WHERE id = $1`,
        [salaId],
      );
    }

    await cliente.query("COMMIT");
  } catch (err) {
    await cliente.query("ROLLBACK");
    throw err;
  } finally {
    cliente.release();
  }
}

// POST /salas/:id/expulsar (PBI-09): el creador saca a otro jugador de una
// sala que aún no ha empezado; su plaza queda libre para que se una otro. El
// servidor de partida se entera al volver a consultar la sala (el backend
// nunca le llama, ver docs/analisis_funcional_app.md §6).
async function expulsarJugador(salaId, creadorId, usuarioId) {
  if (typeof salaId !== "string" || !UUID_RE.test(salaId)) {
    throw new ErrorHttp(400, "id de sala no válido");
  }
  if (typeof usuarioId !== "string" || !UUID_RE.test(usuarioId)) {
    throw new ErrorHttp(400, "usuario_id no válido");
  }
  if (usuarioId === creadorId) {
    throw new ErrorHttp(400, "no puedes expulsarte a ti mismo");
  }

  const cliente = await pool.connect();
  try {
    await cliente.query("BEGIN");

    const { rows: salas } = await cliente.query(
      "SELECT id, estado, capacidad, creador_id FROM salas WHERE id = $1 FOR UPDATE",
      [salaId],
    );
    const sala = salas[0];
    if (!sala) throw new ErrorHttp(404, "la sala no existe");
    if (sala.creador_id !== creadorId) {
      throw new ErrorHttp(403, "solo el creador de la sala puede expulsar");
    }
    if (sala.estado !== "esperando") {
      throw new ErrorHttp(409, "la partida ya ha empezado");
    }

    const { rowCount } = await cliente.query(
      "DELETE FROM sala_participantes WHERE sala_id = $1 AND usuario_id = $2",
      [salaId, usuarioId],
    );
    if (rowCount === 0) {
      throw new ErrorHttp(404, "ese jugador no está en la sala");
    }

    const { rows: restantes } = await cliente.query(
      "SELECT COUNT(*)::int AS total FROM sala_participantes WHERE sala_id = $1",
      [salaId],
    );
    await cliente.query("COMMIT");

    return {
      id: sala.id,
      capacidad: sala.capacidad,
      jugadores_actuales: restantes[0].total,
    };
  } catch (err) {
    await cliente.query("ROLLBACK");
    throw err;
  } finally {
    cliente.release();
  }
}

module.exports = {
  listarSalas,
  crearSala,
  unirseSala,
  salirSala,
  expulsarJugador,
};
