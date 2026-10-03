const express = require("express");
const cors = require("cors");
const fs = require("fs");
const path = require("path");
const yaml = require("js-yaml");
const swaggerUi = require("swagger-ui-express");

const authRoutes = require("./routes/auth");
const lobbyRoutes = require("./routes/lobby");
const historialRoutes = require("./routes/historial");
const rankingRoutes = require("./routes/ranking");

const app = express();
app.use(cors());
app.use(express.json());

app.use("/api/auth", authRoutes);
app.use("/api/salas", lobbyRoutes);
app.use("/api/usuarios", historialRoutes);
app.use("/api/ranking", rankingRoutes);

// Documentación interactiva de la API — fuente: openapi.yaml (ver docs/analisis_funcional_app.md §5)
const openapiDocument = yaml.load(
  fs.readFileSync(path.join(__dirname, "..", "openapi.yaml"), "utf8"),
);
app.get("/api/docs.json", (req, res) => res.json(openapiDocument));
app.use("/api/docs", swaggerUi.serve, swaggerUi.setup(openapiDocument));

app.get("/health", (req, res) => res.json({ ok: true }));

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: "error interno" });
});

module.exports = app;
