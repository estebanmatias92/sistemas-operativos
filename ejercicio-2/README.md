# Ejercicio 2 — Lab 04 Operadores de Redirección

Base: `ejercicio-1.sh` (auth `1234`, inventario en memoria, sin `Nombre`).

## Consigna (resumen)

1. **Reporte** `productos.html`: título + `<table>` con columnas `ID, Nombre, Precio`.
2. **Persistencia** `db/productos.tsv` (`id<TAB>nombre<TAB>precio`): listar, alta, baja y editar. No agregar un producto ya existente.
3. **Autenticación** `db/usuarios.tsv` (`usuario<TAB>sha256` con `sha256sum`): menú `Iniciar sesión` / `Registrar usuario`. Sin contraseñas en texto plano. No agregar un usuario ya existente.
4. **Entrega**: `ejercicio-2.sh` en el repositorio GitHub + notificar en Classroom.

## Uso

```bash
chmod +x ejercicio-2.sh
./ejercicio-2.sh
```

1. El programa crea `db/` con `productos.tsv` y `usuarios.tsv` si no existen.
2. Menú **ACCESO**: `1` iniciar sesión, `2` registrar usuario, `3` salir.
3. Menú **ACCIONES** (post-login): `1` alta, `2` baja, `3` mostrar, `4` editar, `5` generar reporte HTML, `6` salir.

Ejemplo de sesión (alta y reporte):

```
ACCIONES:
1. Alta producto
...
Opción: 1
Ingrese ID: A1
Ingrese Nombre: Yerba Mate
Ingrese Precio: 120.50
Producto A1 guardado.
...
Opción: 5
Reporte generado en productos.html.
```

## Archivos

- `ejercicio-2.sh`: programa (único entregable + `db/` con datos de ejemplo).
- `db/productos.tsv`: tabla de productos (`id<TAB>nombre<TAB>precio`).
- `db/usuarios.tsv`: tabla de usuarios (`usuario<TAB>sha256`, hash, nunca texto plano).
- `productos.html`: reporte derivado (se regenera con la opción 5, no es fuente de verdad).

## Verificación

```bash
bash -n ejercicio-2.sh
./ejercicio-2.sh  # prueba manual punta a punta
```

## Referencia Bash (para `ejercicio-2.sh`)

### 1. Entrada (`read`)

```bash
read -rp "Ingrese ID: " id            # normal: ID, nombre, precio, opción, usuario
read -sp "Contraseña: " pass; echo    # silenciosa: login/registro (alternativa a -rp)
while IFS=$'\t' read -r id nombre precio; do
  echo "ID: $id | Nombre: $nombre"
done < productos.tsv                  # leer TSV línea por línea
```

Alt: `awk -F'\t' '{print $1}' productos.tsv` para solo una columna.

### 2. Salida y redirección

```bash
printf '<h1>Productos</h1>\n' > productos.html     # > crea/sobrescribe (cabecera, tmp)
printf '<tr><td>%s</td></tr>\n' "$id" >> productos.html  # >> agrega (filas, altas)
printf '%s\t%s\t%s\n' "$id" "$nombre" "$precio" >> productos.tsv
cmd < archivo   # alimenta lectura (ver §1)
```

Preferir `printf` sobre `echo` (portable con `\t`, formatos).
Alt para HTML: `cat <<EOF > productos.html` en vez de serie de `>` / `>>`.

### 3. Captura y pipes

```bash
valor=$(echo "1234")                  # $(...) captura stdout en variable
hash=$(echo -n "$pass" | sha256sum)   # pipe a sha256sum
hash=$(echo -n "$pass" | sha256sum | cut -d' ' -f1)  # recorte simple
hash=${hash%% *}                      # alt sin subproceso: quita desde el primer espacio
sub=${cadena:3:8}                     # subcadena (hint de cátedra)
```

### 4. Validación / duplicados

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
