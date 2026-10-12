-- sql/schema.sql — fuente canónica SQL (Lab 05).
-- init_db() en lib/db.sh (hoy TSV) y en lib/db_sqlite.sh (Fase SQLite) deben
-- mantenerse compatibles con este schema. Espejo del heredoc de AGENTS.md.
CREATE TABLE IF NOT EXISTS usuarios(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  hash TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS productos(
  id TEXT PRIMARY KEY,
  nombre TEXT NOT NULL,
  precio TEXT NOT NULL
);
