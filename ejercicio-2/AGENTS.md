# AGENTS.md — ejercicio-2 (Lab 04 Redirección)

Base: `ejercicio-1.sh` (auth `1234`, inventario en memoria, sin `Nombre`).
Objetivo: `ejercicio-2.sh` + `productos.tsv` + `usuarios.tsv` + `productos.html`.

## Contratos (no cambiar sin avisar)

- `db/productos.tsv`: `id<TAB>nombre<TAB>precio` — `id` libre sin tab/vacío (sin `MAX=3`); `nombre` con espacios sí, sin tab; `precio` `^[0-9]+(\.[0-9]{1,2})?$`.
- `db/usuarios.tsv`: `username<TAB>sha256` — `username` es la clave (sin espacios/tab, `^[A-Za-z0-9_.-]+$`); hash hex 64, nunca texto plano.
- `productos.html` (raíz): título + `<table>` con `ID, Nombre, Precio`.
- Altas (productos y usuarios): validar duplicado antes de `>>`.
- Spec ejecutable en cabecera de `ejercicio-2.sh` (`RE_PRECIO`, `RE_USER`); este archivo es solo espejo.

## Convenciones Bash (acordadas)

- Shebang `#!/usr/bin/env bash` + `chmod +x` antes de probar/entregar.
- `set -euo pipefail` en scripts nuevos; ojo: `grep -q` retorna 1 si no encuentra (usar `||` / `if`).
- Nombres: `minusculas_con_guion_bajo` para vars/funcs, `MAYUSCULAS` solo para `declare -r`.
- Siempre citar: `"$id" "$nombre" "$pass"` (nombres con espacios rompen TSV/HTML).
- `printf` sobre `echo` (portable con `\t`, `%.2f` para precio).
- Scope: `declare -r` global para rutas; `local` (con `-i/-r/-a/-A` si hace falta) para todo dentro de funciones. `-i` solo numéricos, `-n` solo para pasar array por nombre. Fuente de verdad = disco (TSV); array en memoria solo como caché temporal dentro de función, nunca estado global persistente.
- Funciones cortas, una tarea cada una (`listar`, `alta`, `generar_html`, `registrar`); `return 0/1`, nunca `exit` adentro.

## Patrones del lab (usar estos, no alternativas)

```bash
[[ -f productos.tsv ]] || touch productos.tsv
while IFS=$'\t' read -r id nombre precio; do ...; done < productos.tsv
printf '<h1>Productos</h1>\n' > productos.html      # > cabecera
printf '<tr><td>%s</td></tr>\n' "$id" >> productos.html  # >> filas/altas
printf '%s\t%s\t%s\n' "$id" "$nombre" "$precio" >> productos.tsv
grep -q -P "^${id}\t" productos.tsv && echo "duplicado"   # check alta
grep -v -P "^${id}\t" productos.tsv > productos.tmp && mv productos.tmp productos.tsv  # baja/editar (portable; no sed -i)
hash=$(echo -n "$pass" | sha256sum | cut -d' ' -f1)  # o ${hash%% *}
read -sp "Contraseña: " pass; echo  # passwords ocultas; read -rp para resto
```

## Verificación

```bash
bash -n ejercicio-2.sh
shellcheck ejercicio-2.sh  # limpio antes de entregar
chmod +x ejercicio-2.sh && ./ejercicio-2.sh  # prueba manual punta a punta
```

## Trabajo con el usuario

- Prioridad: entender antes que implementar. Dictar de a un micro-paso: código + explicación breve de cada instrucción/expresión, probar, recién avanzar.
- No reintroducir `MAX=3` para productos (IDs libres) ni `declare -A inventario` global persistente; no usar `sed -i` ni `awk` donde el lab pide `grep`+`tmp+mv`.
- Entrega: archivo `ejercicio-2.sh` en este dir + notificar en Classroom.
