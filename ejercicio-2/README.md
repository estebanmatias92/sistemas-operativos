# Code — Lab 04 Operadores de Redirección

Base: `ejercicio-1.sh` (auth `1234`, inventario en memoria, sin `Nombre`).

## Referencia Bash (para `ejercicio-2.sh`)

### 1. Entrada (`read`) — O2/O3

```bash
read -rp "Ingrese ID: " id            # normal: ID, nombre, precio, opción, usuario
read -sp "Contraseña: " pass; echo    # silenciosa: login/registro (alternativa a -rp)
while IFS=$'\t' read -r id nombre precio; do
  echo "ID: $id | Nombre: $nombre"
done < productos.tsv                  # leer TSV línea por línea
```

Alt: `awk -F'\t' '{print $1}' productos.tsv` para solo una columna.

### 2. Salida y redirección — O1/O2/O3

```bash
printf '<h1>Productos</h1>\n' > productos.html     # > crea/sobrescribe (cabecera, tmp)
printf '<tr><td>%s</td></tr>\n' "$id" >> productos.html  # >> agrega (filas, altas)
printf '%s\t%s\t%s\n' "$id" "$nombre" "$precio" >> productos.tsv
cmd < archivo   # alimenta lectura (ver §1)
```

Preferir `printf` sobre `echo` (portable con `\t`, formatos).
Alt para HTML: `cat <<EOF > productos.html` en vez de serie de `>` / `>>`.

### 3. Captura y pipes — O3

```bash
valor=$(echo "1234")                  # $(...) captura stdout en variable
hash=$(echo -n "$pass" | sha256sum)   # pipe a sha256sum
hash=$(echo -n "$pass" | sha256sum | cut -d' ' -f1)  # recorte simple
hash=${hash%% *}                      # alt sin subproceso: quita desde el primer espacio
sub=${cadena:3:8}                     # subcadena (hint de cátedra)
```

### 4. Validación / duplicados — O2/O3

```bash
[[ -f productos.tsv ]] || touch productos.tsv
grep -q -P "^${id}\t" productos.tsv && echo "ya existe"      # ¿ID existe?
grep -q -P "^${user}\t" usuarios.tsv && echo "ya existe"     # ¿usuario existe?
# editar/baja: reescribir vía tmp + mv (recomendado, portable)
grep -v -P "^${id}\t" productos.tsv > productos.tmp && mv productos.tmp productos.tsv
```

Alt: `cut -f1 productos.tsv | grep -qx "$id"`, o `awk -F'\t'`, o `sed -i` (más corto pero menos didáctico para el lab).

### 5. Contratos mínimos

- `productos.tsv`: `ID<TAB>Nombre<TAB>Precio`
- `usuarios.tsv`: `usuario<TAB>sha256`
- `productos.html`: título + `<table>` con columnas ID, Nombre, Precio
- Altas (productos y usuarios): validar duplicado antes de `>>`.
