const express = require("express");
const router = express.Router();

// GET /api/usuarios/:id/historial — PBI-06
router.get("/:id/historial", async (req, res) => {
  res.status(501).json({ error: "no implementado" });
});

module.exports = router;
