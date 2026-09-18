const express = require("express");
const router = express.Router();

// GET /api/salas — listar salas (PBI-02)
router.get("/", async (req, res) => {
  res.status(501).json({ error: "no implementado" });
});

// POST /api/salas — crear sala
router.post("/", async (req, res) => {
  res.status(501).json({ error: "no implementado" });
});

// POST /api/salas/:id/unirse
router.post("/:id/unirse", async (req, res) => {
  res.status(501).json({ error: "no implementado" });
});

// POST /api/salas/:id/expulsar — PBI-09, solo el creador de la sala
router.post("/:id/expulsar", async (req, res) => {
  res.status(501).json({ error: "no implementado" });
});

module.exports = router;
