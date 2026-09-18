const express = require("express");
const router = express.Router();

// POST /api/auth/registro — ver docs/analisis_funcional_app.md §5 (PBI-01)
router.post("/registro", async (req, res) => {
  // TODO: validar body, hashear password con bcrypt, insertar en tabla usuarios
  res.status(501).json({ error: "no implementado" });
});

// POST /api/auth/login
router.post("/login", async (req, res) => {
  // TODO: verificar credenciales contra la tabla usuarios, firmar JWT
  res.status(501).json({ error: "no implementado" });
});

module.exports = router;
