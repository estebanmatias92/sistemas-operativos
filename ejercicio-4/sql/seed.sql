-- sql/seed.sql — datos ejemplo para var/db/data.sq3 de entrega.
-- Única semilla canónica (INSERT OR IGNORE, idempotente). Hash = sha256("12345").
INSERT OR IGNORE INTO productos(id,nombre,precio) VALUES('1','escoba','3000');
INSERT OR IGNORE INTO productos(id,nombre,precio) VALUES('2','balde','2000');
INSERT OR IGNORE INTO usuarios(username,hash) VALUES('matt','5994471abb01112afcc18159f6cc74b4f511b99806da59b3caf5a9c173cacfc5');
INSERT OR IGNORE INTO usuarios(username,hash) VALUES('jeff','5994471abb01112afcc18159f6cc74b4f511b99806da59b3caf5a9c173cacfc5');
