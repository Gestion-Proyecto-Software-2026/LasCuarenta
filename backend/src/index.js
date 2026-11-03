// Carga backend/.env si existe (al arrancar fuera de Docker). Las variables ya
// definidas en el entorno, como las de docker-compose.yml, tienen prioridad.
try {
  process.loadEnvFile();
} catch (err) {
  if (err.code !== "ENOENT") throw err;
}

// Con `restart: unless-stopped` (docker-compose.yml) un crash nativo (p. ej. un
// módulo nativo como bcrypt que no carga bien en la imagen) reinicia el
// contenedor en silencio: sin estos handlers no queda ni rastro en los logs.
process.on("uncaughtException", (err) => {
  console.error("uncaughtException:", err);
});
process.on("unhandledRejection", (motivo) => {
  console.error("unhandledRejection:", motivo);
});
process.on("exit", (codigo) => {
  console.error(`El proceso del backend termina con código ${codigo}`);
});
for (const señal of ["SIGTERM", "SIGINT"]) {
  process.on(señal, () => {
    console.error(`Backend recibió ${señal}, cerrando`);
    process.exit(0);
  });
}

const app = require("./app");

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Backend escuchando en :${PORT}`));
