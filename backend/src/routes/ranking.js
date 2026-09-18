const express = require("express");
const router = express.Router();

// GET /api/ranking — PBI-07
router.get("/", async (req, res) => {
  res.status(501).json({ error: "no implementado" });
});

module.exports = router;
