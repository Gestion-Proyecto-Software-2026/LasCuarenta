const express = require("express");
const requireAuth = require("../middleware/auth");
const lobbyService = require("../services/lobbyService");
const { ErrorHttp } = require("../utils/errorHttp");
const router = express.Router();

function manejarError(err, res, next) {
  if (err instanceof ErrorHttp) {
    return res.status(err.status).json({ error: err.message });
  }
  next(err);
}

router.use(requireAuth);

// GET /api/salas?juego=guinote — salas en espera con plazas libres (PBI-02)
router.get("/", async (req, res, next) => {
  try {
    const salas = await lobbyService.listarSalas(req.query);
    res.status(200).json(salas);
  } catch (err) {
    manejarError(err, res, next);
  }
});

// POST /api/salas — crea una sala y sienta al creador en la posición 0 (PBI-02)
router.post("/", async (req, res, next) => {
  try {
    const sala = await lobbyService.crearSala(req.body || {}, req.usuario.id);
    res.status(201).json(sala);
  } catch (err) {
    manejarError(err, res, next);
  }
});

// POST /api/salas/:id/unirse (PBI-02)
router.post("/:id/unirse", async (req, res, next) => {
  try {
    const sala = await lobbyService.unirseSala(req.params.id, req.usuario.id);
    res.status(200).json(sala);
  } catch (err) {
    manejarError(err, res, next);
  }
});

// POST /api/salas/:id/expulsar — PBI-09, solo el creador de la sala
router.post("/:id/expulsar", (req, res) => {
  res.status(501).json({ error: "no implementado" });
});

module.exports = router;
