# El buscador de contactos de Llamadas se congelaba (2026-09-03 y 2026-09-21)

Con **2556 contactos**, escribir en el buscador de la pestaña *Contactos* de Llamadas (`gnome-calls`)
congelaba la aplicación **hasta ~25 s por tecla**. Lo peor era **una sola letra**: al añadir más, con menos
resultados, iba más rápido.

## Cómo se midió

Calls atiende `org.gtk.Actions.DescribeAll` **en su bucle principal**. Una sonda que llama a esa acción en
bucle mide cuánto está bloqueado ese bucle, sin instrumentar la aplicación:

```
en reposo:            mediana ~15 ms   (coste de lanzar gdbus)
tecleando una letra:  4834 ms · 25039 ms · 24673 ms · 15753 ms
```

El bloqueo **escala con el número de resultados que hay que pintar**, no con el total barrido: `GtkListBox`
crea una fila (avatar + un botón por cada número de teléfono) por cada acierto que llega del modelo.

## Los dos parches

- **`0001`** — `gtk_filter_list_model_set_incremental (…, TRUE)` en `calls_contacts_box_init()`. No hace menos
  trabajo: lo **reparte** en ratos ociosos (tandas de 512 elementos), devolviendo el control al bucle principal.
  El mismo cambio en `gnome-contacts` bajó el congelado de ~1050 ms a ~340 ms por pulsación, medido en vivo.
- **`0002`** — **no filtrar hasta que haya 3 caracteres** (sin contar los espacios de los extremos). Con una o
  dos letras casan cientos de contactos, y filtrar y pintar todas esas filas en cada pulsación era el peor caso
  sin ayudar a encontrar a nadie. Por debajo del mínimo la lista se queda entera y pasar de una a dos letras no
  refiltra nada; al llegar a tres filtra como siempre.

## Trampas al empaquetarlo

- **`pkgrel=100` a propósito**: con `r1`, una recompilación del repositorio oficial (`r2`, `r3`…) sustituye el
  paquete en un `apk upgrade` y **los parches se pierden en silencio**. Una versión nueva de verdad (50.1) sí lo
  sustituye: hay que comprobarlo tras cada actualización.
- Con **pmbootstrap**, `makedepends="` debe empezar en la **columna 0**: si va indentado, el analizador lo lee
  vacío, no instala nada y la compilación muere con `abuild-meson: not found`.
- `calls` necesita además `mobile-broadband-provider-info` y `abuild-meson` entre las dependencias de
  compilación; el primero lo exige `meson` y solo lo arrastra el `modemmanager` de ejecución, que no está en el
  chroot de compilación.

## Lo que no se llegó a hacer

La palanca de fondo no es código: **1245 de ~1260 nombres están en las dos libretas** (la de Google y la de
WebDAV), y `folks` apenas enlaza 64 pares, así que la aplicación carga, ordena y recorre todo dos veces. Quitar
una de las dos partiría por la mitad el tiempo de abrir, el de buscar y la memoria. No se hizo: es una decisión
sobre los datos del usuario.
