const express = require("express");
const jwt = require("jsonwebtoken");
const router = express.Router();
const authService = require("../services/authService");

const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || "24h";

function manejarError(err, res, next) {
  if (err instanceof authService.AuthError) {
    return res.status(err.status).json({ error: err.message });
  }
  next(err);
}

// POST /api/auth/registro — ver docs/analisis_funcional_app.md §5 (PBI-01)
router.post("/registro", async (req, res, next) => {
  try {
    const usuario = await authService.registrar(req.body || {});
    res.status(201).json(usuario);
  } catch (err) {
    manejarError(err, res, next);
  }
});

// POST /api/auth/login
router.post("/login", async (req, res, next) => {
  try {
    const usuario = await authService.login(req.body || {});
    const token = jwt.sign({ id: usuario.id }, process.env.JWT_SECRET, {
      expiresIn: JWT_EXPIRES_IN,
    });
    res.status(200).json({ token, usuario });
  } catch (err) {
    manejarError(err, res, next);
  }
});

// POST /api/auth/recuperar — solicita un código de recuperación por correo
router.post("/recuperar", async (req, res, next) => {
  try {
    const resultado = await authService.solicitarRecuperacion(req.body || {});
    res.status(200).json(resultado);
  } catch (err) {
    manejarError(err, res, next);
  }
});

// POST /api/auth/restablecer — fija una contraseña nueva a partir del código
router.post("/restablecer", async (req, res, next) => {
  try {
    const resultado = await authService.restablecerPassword(req.body || {});
    res.status(200).json(resultado);
  } catch (err) {
    manejarError(err, res, next);
  }
});

module.exports = router;
