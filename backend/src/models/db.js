const { Pool } = require("pg");

// Ver docs/analisis_funcional_app.md §4 para el esquema completo.
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

module.exports = pool;
