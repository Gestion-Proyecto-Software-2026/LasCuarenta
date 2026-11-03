const express = require("express");
const requireInternalSecret = require("../middleware/internalAuth");
const internoService = require("../services/internoService");
const { ErrorHttp } = require("../utils/errorHttp");
const router = express.Router();

function manejarError(err, res, next) {
  if (err instanceof ErrorHttp) {
    return res.status(err.status).json({ error: err.message });
  }
  next(err);
}

router.use(requireInternalSecret);

// GET /api/interno/salas/:id — solo lo llama el servidor de partida
router.get("/salas/:id", async (req, res, next) => {
  try {
    const sala = await internoService.obtenerSala(req.params.id);
    res.status(200).json(sala);
  } catch (err) {
    manejarError(err, res, next);
  }
});

// POST /api/interno/partidas — solo lo llama el servidor de partida
router.post("/partidas", async (req, res, next) => {
  try {
    const partida = await internoService.registrarPartida(req.body || {});
    res.status(201).json(partida);
  } catch (err) {
    manejarError(err, res, next);
  }
});

module.exports = router;
