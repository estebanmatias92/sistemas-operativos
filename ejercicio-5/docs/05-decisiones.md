# 05 — Decisiones (ADRs)

Registro corto de decisiones de arquitectura. Cada una indica contexto,
decisión, consecuencias y alternativas descartadas. Estado y fecha son los del
cierre del Lab 07 (2026-11-12).

## ADR-001 — La web es un tercer client de presentación

- **Estado:** aceptada.
- **Contexto:** ya existen CLI y TUI sobre una API en capas; el Lab 07 pide una
  interfaz web sin romper los clients existentes.
- **Decisión:** `lib/web/` traduce HTTP/JSON-RPC a llamadas de `lib/api/`. No
  arma SQL, no duplica validaciones y no conoce `sqlite3`.
- **Consecuencias:** una sola lógica de negocio para los tres clients; la web
  solo aporta transporte, sesión y serialización JSON.
- **Alternativas:** reimplementar reglas en la web (descartada: divergencia y
  doble auditoría); usar CGI/FastCGI (descartada: más infraestructura que la
  necesaria para el lab).

## ADR-002 — Variantes `*_data` en la API

- **Estado:** aceptada.
- **Contexto:** los handlers web necesitan datos, no texto formateado para
  humanos; CLI/TUI necesitan mensajes exactos.
- **Decisión:** cada caso de uso tiene una variante `*_data` que devuelve
  TSV/valores por stdout y códigos `0/10/11/12`; la función histórica formatea
  el mensaje y traduce cualquier fallo a `return 1`.
- **Consecuencias:** la web parsea TSV estable; los mensajes de CLI/TUI quedan
  intactos. Los códigos permiten mapear a RPC sin repetir reglas.
- **Alternativas:** parsear la salida humana (descartada: frágil); devolver JSON
  desde la API (descartada: acopla la API a la web y mete `jq` en `lib/api`).

## ADR-003 — Errores de aplicación con HTTP 200

- **Estado:** aceptada.
- **Contexto:** JSON-RPC 2.0 define errores en el envelope, no en el status
  HTTP; el ejemplo del profesor usa HTTP 200.
- **Decisión:** los errores de aplicación (`-32xxx`) viajan con HTTP 200 y
  envelope `error`. Los 4xx se reservan para transporte/estáticos (`400`, `404`,
  `413`).
- **Consecuencias:** el cliente distingue errores por `error.code`; el status
  HTTP describe el transporte. Coherente con el ejemplo didáctico.
- **Alternativas:** mapear cada código RPC a un status HTTP (descartada:
  ambigua y no estándar para JSON-RPC).

## ADR-004 — Sesión en archivo, fork-safe

- **Estado:** aceptada.
- **Contexto:** `socat` hace `fork` por conexión; no hay memoria compartida
  entre requests.
- **Decisión:** `var/session/sessions.tsv` con `flock` (compartido para
  validar, exclusivo para crear/revocar/limpiar) y reescritura con temporal +
  `mv`.
- **Consecuencias:** la sesión sobrevive a los forks y a un restart del server;
  no hay carrera entre validaciones y revocaciones.
- **Alternativas:** variable global/array (descartada: no se comparte);
  SQLite para sesiones (descartada: más superficie y acopla la web al model).

## ADR-005 — Token, TTL y permisos de sesión

- **Estado:** aceptada.
- **Contexto:** hace falta un bearer token simple, revocable y con vencimiento.
- **Decisión:** token de 32 bytes de `/dev/urandom` hasheado con SHA-256 (64
  hex), TTL de 3600 s (`SESSION_TTL`), directorio `700` y archivo `600`.
  `auth.login` devuelve token y `expires_at`; `auth.logout` revoca.
- **Consecuencias:** token difícil de adivinar, expiración acotada y archivo
  privado. No se loguean tokens ni contraseñas.
- **Alternativas:** JWT (descartada: firma/gestión innecesaria para el lab);
  sesión en memoria (descartada por fork); token sin hash (descartada: el
  archivo quedaría con el secreto en claro).

## ADR-006 — Resolución de estáticos con `realpath`

- **Estado:** aceptada.
- **Contexto:** hay que servir `static/` y `var/report/` sin permitir traversal.
- **Decisión:** resolver con `realpath -m`, comparar contra el root con `/`
  final y exigir archivo regular; `/report/<archivo>` mapea a
  `dirname(PRODUCTS_HTML)`. MIME explícito, sin `xdg-mime`.
- **Consecuencias:** `..`, symlinks y prefijos engañosos (`/var/report-otro`)
  quedan fuera; el comportamiento es determinista y no depende del escritorio.
- **Alternativas:** concatenar strings (descartada: traversal); `xdg-mime`
  (descartada: dependencia de entorno gráfico).

## ADR-007 — Métodos no soportados y alcance JSON-RPC

- **Estado:** aceptada.
- **Contexto:** el lab pide GET/POST y no exige batch ni notificaciones.
- **Decisión:** cualquier método HTTP distinto de GET/POST devuelve `-32005` con
  HTTP 200. Batch (array raíz) se rechaza con `-32600`; notificaciones sin `id`
  se responden con `id: null`.
- **Consecuencias:** superficie chica y explícita; el cliente sabe qué esperar.
- **Alternativas:** implementar batch/notificaciones (descartada: fuera de
  alcance y sin caso de uso en la UI).

## ADR-008 — UI end-user, sin panel de debug

- **Estado:** aceptada.
- **Contexto:** el ejemplo del profesor incluye un panel de JSON crudo y una
  tabla de procedimientos; la entrega debe ser una app usable.
- **Decisión:** la UI tiene login/registro, cabecera con usuario, inventario,
  alta/edición, baja con confirmación, reporte y mensajes de estado. Los datos
  se pintan con `textContent`; el token vive en `sessionStorage` y viaja en
  `params.token`. Sin cookies ni CORS.
- **Consecuencias:** experiencia de usuario final y menor riesgo de XSS por
  interpolación de datos. El panel de debug queda en el ejemplo intacto.
- **Alternativas:** copiar el panel del ejemplo (descartada: no es una app);
  `innerHTML` para filas (descartada: inyección de HTML).

## ADR-009 — Binding por defecto `0.0.0.0`

- **Estado:** aceptada.
- **Contexto:** el ejemplo del profesor escucha en todas las interfaces; el lab
  se prueba a veces desde otro dispositivo de la red local.
- **Decisión:** default `0.0.0.0:8080`, configurable con `HTTP_SERVER_HOST` y
  `HTTP_SERVER_PORT`; documentar `127.0.0.1` para uso local.
- **Consecuencias:** funciona en red local sin configuración, pero expone el
  servicio sin TLS. La documentación y el `--help` lo advierten.
- **Alternativas:** default `127.0.0.1` (más seguro, pero rompe la paridad con
  el ejemplo y el acceso desde el aula).

## ADR-010 — Fronteras de capas verificadas por `make check`

- **Estado:** aceptada.
- **Contexto:** las reglas de capas se degradan si solo están documentadas.
- **Decisión:** `make check` falla si `sqlite3` aparece fuera de `lib/model`,
  `whiptail`/`read -rp` fuera de `lib/ui`, `socat` fuera de `bin/server` +
  `lib/web/dispatch.sh`, o `jq` fuera de `lib/web`.
- **Consecuencias:** la arquitectura queda ejecutable; un cambio accidental
  rompe el build, no la producción.
- **Alternativas:** revisión manual (descartada: se olvida); linting más pesado
  (fuera de alcance).

## ADR-011 — Documentación como código con PlantUML

- **Estado:** aceptada.
- **Contexto:** el sistema ya tiene tres clients, sesión y varios contratos; los
  diagramas ayudan a entenderlo y a defenderlo.
- **Decisión:** los diagramas viven en `docs/diagrams/*.puml`, se compilan a SVG
  con `make docs` y los SVG se versionan. Los documentos de `docs/` enlazan los
  SVG; el contrato canónico está en `03-referencia.md`.
- **Consecuencias:** diagramas revisables en diff, regenerables y sin edición
  manual del SVG. PlantUML es dependencia **solo de documentación**, no del
  runtime.
- **Alternativas:** Mermaid embebido (descartada por elección del equipo);
  imágenes binarias sueltas (descartadas: no se pueden revisar).
