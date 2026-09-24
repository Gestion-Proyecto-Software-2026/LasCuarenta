// Carga backend/.env si existe (al arrancar fuera de Docker). Las variables ya
// definidas en el entorno, como las de docker-compose.yml, tienen prioridad.
try {
  process.loadEnvFile();
} catch (err) {
  if (err.code !== "ENOENT") throw err;
}

const app = require("./app");

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Backend escuchando en :${PORT}`));
