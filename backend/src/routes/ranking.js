const express = require("express");
const rankingService = require("../services/rankingService");
const { ErrorHttp } = require("../utils/errorHttp");
const router = express.Router();

// GET /api/ranking?juego=guinote — clasificación pública (PBI-07), sin token.
router.get("/", async (req, res, next) => {
  try {
    const ranking = await rankingService.obtenerRanking(req.query);
    res.status(200).json(ranking);
  } catch (err) {
    if (err instanceof ErrorHttp) {
      return res.status(err.status).json({ error: err.message });
    }
    next(err);
  }
});

module.exports = router;
