const express = require("express");
const cors = require("cors");

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

app.get("/health", (req, res) => res.json({ ok: true }));

module.exports = app;
