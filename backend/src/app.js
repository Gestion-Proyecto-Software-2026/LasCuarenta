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
const internoRoutes = require("./routes/interno");

const app = express();
app.use(cors());
app.use(express.json());

// Log mínimo de cada petición (silenciado en los tests, donde NODE_ENV=test):
// sirve para saber qué ruta se estaba sirviendo justo antes de un crash, que
// con `restart: unless-stopped` (docker-compose.yml) reinicia el contenedor
// en silencio y, si no, no queda rastro de qué petición lo causó.
if (process.env.NODE_ENV !== "test") {
  app.use((req, res, next) => {
    const inicio = Date.now();
    console.log(`-> ${req.method} ${req.originalUrl}`);
    res.on("finish", () => {
      console.log(
        `<- ${req.method} ${req.originalUrl} ${res.statusCode} (${Date.now() - inicio}ms)`,
      );
    });
    next();
  });
}

app.use("/api/auth", authRoutes);
app.use("/api/salas", lobbyRoutes);
app.use("/api/usuarios", historialRoutes);
app.use("/api/ranking", rankingRoutes);
app.use("/api/interno", internoRoutes);

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
