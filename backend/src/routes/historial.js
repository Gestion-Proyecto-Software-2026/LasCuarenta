const express = require("express");
const requireAuth = require("../middleware/auth");
const historialService = require("../services/historialService");
const { ErrorHttp } = require("../utils/errorHttp");
const router = express.Router();

function manejarError(err, res, next) {
  if (err instanceof ErrorHttp) {
    return res.status(err.status).json({ error: err.message });
  }
  next(err);
}

router.use(requireAuth);

// GET /api/usuarios/me/privacidad — si el historial del usuario es público (PBI-06)
router.get("/me/privacidad", async (req, res, next) => {
  try {
    const privacidad = await historialService.obtenerPrivacidad(req.usuario.id);
    res.status(200).json(privacidad);
  } catch (err) {
    manejarError(err, res, next);
  }
});

// PUT /api/usuarios/me/privacidad — { historial_publico: boolean } (PBI-06)
router.put("/me/privacidad", async (req, res, next) => {
  try {
    const privacidad = await historialService.cambiarPrivacidad(
      req.usuario.id,
      req.body || {},
    );
    res.status(200).json(privacidad);
  } catch (err) {
    manejarError(err, res, next);
  }
});

// GET /api/usuarios/:id/historial?juego=&limite= — :id puede ser `me` (PBI-06)
router.get("/:id/historial", async (req, res, next) => {
  try {
    const partidas = await historialService.listarHistorial(
      req.params.id,
      req.usuario.id,
      req.query,
    );
    res.status(200).json(partidas);
  } catch (err) {
    manejarError(err, res, next);
  }
});

// GET /api/usuarios/:id/estadisticas — :id puede ser `me` (PBI-06)
router.get("/:id/estadisticas", async (req, res, next) => {
  try {
    const estadisticas = await historialService.obtenerEstadisticas(
      req.params.id,
      req.usuario.id,
    );
    res.status(200).json(estadisticas);
  } catch (err) {
    manejarError(err, res, next);
  }
});

module.exports = router;
