const bcrypt = require("bcrypt");
const crypto = require("crypto");
const pool = require("../models/db");
const { enviarCorreo } = require("../utils/mailer");

// El cliente nunca manda la contraseña en claro: envía su SHA-256 en hex
// (64 caracteres). El backend aplica bcrypt sobre ese hash antes de guardarlo
// (ver docs/analisis_funcional_app.md §5): ni lo que viaja por la red ni lo
// que se guarda en la base de datos sirve por sí solo como contraseña.
const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS || 10);
const CODIGO_TTL_MIN = Number(process.env.RECOVERY_CODE_TTL_MIN || 15);

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const HASH_RE = /^[a-f0-9]{64}$/i;
const CODIGO_RE = /^\d{6}$/;

class AuthError extends Error {
  constructor(status, mensaje) {
    super(mensaje);
    this.status = status;
  }
}

function validarEmail(email) {
  if (typeof email !== "string" || !EMAIL_RE.test(email)) {
    throw new AuthError(400, "email inválido");
  }
}

function validarPasswordHash(hash) {
  if (typeof hash !== "string" || !HASH_RE.test(hash)) {
    throw new AuthError(
      400,
      "password_hash inválido: se espera SHA-256 en hexadecimal",
    );
  }
}

function generarCodigo() {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, "0");
}

function hashCodigo(codigo) {
  return crypto.createHash("sha256").update(codigo).digest("hex");
}

async function registrar({ email, password_hash, nombre_visible }) {
  validarEmail(email);
  validarPasswordHash(password_hash);

  const nombreVisible =
    typeof nombre_visible === "string" ? nombre_visible.trim() : "";
  if (!nombreVisible) throw new AuthError(400, "nombre_visible inválido");

  const emailNorm = email.toLowerCase();
  const hashAlmacenado = await bcrypt.hash(password_hash, SALT_ROUNDS);

  try {
    const { rows } = await pool.query(
      `INSERT INTO usuarios (email, password_hash, nombre_visible)
       VALUES ($1, $2, $3)
       RETURNING id, email, nombre_visible`,
      [emailNorm, hashAlmacenado, nombreVisible],
    );
    return rows[0];
  } catch (err) {
    if (err.code === "23505") {
      throw new AuthError(409, "el correo ya está registrado");
    }
    throw err;
  }
}

async function login({ email, password_hash }) {
  validarEmail(email);
  validarPasswordHash(password_hash);

  const { rows } = await pool.query(
    "SELECT id, email, nombre_visible, password_hash FROM usuarios WHERE email = $1",
    [email.toLowerCase()],
  );
  const usuario = rows[0];
  if (!usuario) throw new AuthError(401, "credenciales inválidas");

  const coincide = await bcrypt.compare(password_hash, usuario.password_hash);
  if (!coincide) throw new AuthError(401, "credenciales inválidas");

  return {
    id: usuario.id,
    email: usuario.email,
    nombre_visible: usuario.nombre_visible,
  };
}

async function solicitarRecuperacion({ email }) {
  validarEmail(email);
  const emailNorm = email.toLowerCase();

  const { rows } = await pool.query(
    "SELECT id FROM usuarios WHERE email = $1",
    [emailNorm],
  );
  const usuario = rows[0];

  // Se responde siempre lo mismo exista o no la cuenta, para no filtrar qué
  // correos están registrados.
  if (usuario) {
    const codigo = generarCodigo();
    const expiraEn = new Date(Date.now() + CODIGO_TTL_MIN * 60_000);
    await pool.query(
      `INSERT INTO codigos_recuperacion (usuario_id, codigo_hash, expira_en)
       VALUES ($1, $2, $3)`,
      [usuario.id, hashCodigo(codigo), expiraEn],
    );
    await enviarCorreo({
      to: emailNorm,
      subject: "Recupera tu contraseña — Cartas Online",
      text: `Tu código de recuperación es ${codigo}. Caduca en ${CODIGO_TTL_MIN} minutos.`,
    });
  }

  return {
    mensaje: "si el correo existe, se ha enviado un código de recuperación",
  };
}

async function restablecerPassword({ email, codigo, password_hash }) {
  validarEmail(email);
  validarPasswordHash(password_hash);
  if (typeof codigo !== "string" || !CODIGO_RE.test(codigo)) {
    throw new AuthError(400, "código inválido o caducado");
  }
  const emailNorm = email.toLowerCase();

  const { rows: usuarios } = await pool.query(
    "SELECT id FROM usuarios WHERE email = $1",
    [emailNorm],
  );
  const usuario = usuarios[0];
  if (!usuario) throw new AuthError(400, "código inválido o caducado");

  const { rows: codigos } = await pool.query(
    `SELECT id FROM codigos_recuperacion
     WHERE usuario_id = $1 AND codigo_hash = $2 AND usado = false AND expira_en > now()`,
    [usuario.id, hashCodigo(codigo)],
  );
  if (!codigos[0]) throw new AuthError(400, "código inválido o caducado");

  const hashAlmacenado = await bcrypt.hash(password_hash, SALT_ROUNDS);

  await pool.query("UPDATE usuarios SET password_hash = $1 WHERE id = $2", [
    hashAlmacenado,
    usuario.id,
  ]);
  // Invalida también cualquier otro código pendiente para esa cuenta.
  await pool.query(
    "UPDATE codigos_recuperacion SET usado = true WHERE usuario_id = $1 AND usado = false",
    [usuario.id],
  );

  return { mensaje: "contraseña actualizada" };
}

module.exports = {
  AuthError,
  registrar,
  login,
  solicitarRecuperacion,
  restablecerPassword,
};
