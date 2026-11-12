# Ejercicio 5 — Lab 07 Arquitectura de Capas / Web RPC

Base: `ejercicio-4` (Lab 06: capas `ui → api → model → config`, SQLite,
`system.log`/`error.log`, reporte `productos.html`, clients CLI y TUI).

## Idea

La app ya tiene dos clients (`--cli`, `--tui`) sobre una misma API. El Lab 07
agrega un **tercer client de presentación**: una interfaz web sobre HTTP +
JSON-RPC 2.0 que traduce requests a llamadas de `lib/api/`, sin armar SQL ni
duplicar reglas. El flujo sigue siendo:

```text
web → api → model → config
        (logging cross-cutting, validators/crypto puros)
```

`socat` abre el puerto y hace `fork` por conexión: no hay estado en memoria
compartida. La sesión vive en archivo y los datos en SQLite.

## Estado

- CLI/TUI heredados de Lab 06: funcionando (`./ejercicio-5.sh --cli|--tui`).
- Interfaz web (`server.sh`, `bin/server`, `lib/web/`, `static/`): en
  implementación por checkpoints (HTTP estático → envelope RPC → sesión/auth →
  CRUD → reporte → UI → cierre).

La documentación completa de dependencias, arranque, métodos RPC y ejemplos
`curl` se completa al cerrar el lab.
