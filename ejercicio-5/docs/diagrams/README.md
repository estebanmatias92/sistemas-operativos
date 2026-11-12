# Diagramas

Fuentes PlantUML del Lab 07. El SVG compilado se versiona junto al `.puml` y es
lo que enlazan los documentos de `docs/`.

## Inventario

| Fuente | Compilado | Tipo | Se usa en |
|---|---|---|---|
| `runtime.puml` | `runtime.svg` | deployment | [01 — Arquitectura](../01-arquitectura.md) |
| `layers.puml` | `layers.svg` | component | [01 — Arquitectura](../01-arquitectura.md) |
| `request-lifecycle.puml` | `request-lifecycle.svg` | activity | [02 — Flujos](../02-flujos.md) |
| `rpc-private.puml` | `rpc-private.svg` | sequence | [02 — Flujos](../02-flujos.md) |
| `session-states.puml` | `session-states.svg` | state | [02 — Flujos](../02-flujos.md) |
| `data-model.puml` | `data-model.svg` | ER | [03 — Referencia](../03-referencia.md) |

## Regenerar

```bash
make docs        # compila todos los .puml a .svg
make docs-check  # valida sintaxis (si plantuml está instalado)
```

`make docs`:

1. Verifica que `plantuml` exista.
2. Ejecuta `plantuml --svg --charset UTF-8 --disable-metadata --stop-on-error`.
3. Inyecta un `<rect class="docs-background">` blanco para que el SVG sea
   legible también en GitHub con tema oscuro.

Requiere PlantUML + Java + GraphViz. Probado con PlantUML `1.2026.8` y GraphViz
`16.1.0`.

## Convenciones

- **No editar el `.svg` a mano**: se regenera y se pisa.
- Fondo blanco explícito (el `rect` lo agrega `make docs`); no quitarlo.
- Paleta por capa: azul = presentación/entrypoints, verde = API, ámbar = modelo
  y notas, gris = base/archivos.
- Etiquetas en español; identificadores de código tal cual (`*_data`,
  `session_validate`, etc.).
- Si cambia un flujo o una frontera de capas, actualizar el `.puml` y
  regenerar; si cambia el contrato, actualizar además
  [03 — Referencia](../03-referencia.md).
