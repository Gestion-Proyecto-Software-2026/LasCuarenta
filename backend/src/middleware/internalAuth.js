// Autenticación servidor-a-servidor para /api/interno/* (solo la usa el servidor de partida).
module.exports = function requireInternalSecret(req, res, next) {
  const secreto = req.headers["x-internal-secret"];
  if (!secreto || secreto !== process.env.INTERNAL_API_SECRET) {
    return res.status(401).json({ error: "no autorizado" });
  }
  next();
};
