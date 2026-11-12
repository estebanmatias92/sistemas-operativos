-- sql/schema.sql — fuente canónica SQL.
-- El ÚNICO que la aplica es scripts/deploy.sh (`make init`); la app solo require_db.
-- IDs autogenerados en ambas tablas (el alta nunca pide id manual).
CREATE TABLE IF NOT EXISTS usuarios(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  hash TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS productos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nombre TEXT NOT NULL,
  precio TEXT NOT NULL
);
