# PortDeck

App de barra de estado para macOS que arranca, detiene y vigila los proyectos que corrés en localhost.

- **Menú:** cada proyecto con su puerto y estado (activo, arrancando, inactivo, puerto ocupado por otro proceso, error). Arrancar, detener, abrir en el navegador, arrancar en otro puerto y ver el log.
- **Ventana:** agregar, editar y quitar proyectos. Al elegir la carpeta, propone un comando según lo que encuentra (`package.json`, `artisan`, `manage.py`, `compose.yaml`).
- **Inicio:** se abre sola al iniciar sesión (Ajustes del Sistema → Ítems de inicio) y puede arrancar los proyectos marcados.

## Cómo arranca cada proyecto

El comando se corre con `zsh -c` dentro de la carpeta del proyecto, con el entorno de tu shell interactivo (nvm, Homebrew y el resto del PATH). `{PORT}` se reemplaza por el puerto elegido y además se exporta `$PORT`:

```text
npm run dev -- --port {PORT}
php artisan serve --port={PORT}
npm start                      # si la app lee $PORT
```

Arrancar en otro puerto sólo funciona si el comando usa `{PORT}` o la app respeta `$PORT`.

Cada proyecto corre en su propio grupo de procesos: detenerlo manda `SIGTERM` al grupo entero y `SIGKILL` a los 5 s si sigue vivo. Si PortDeck se cierra sin detenerlos, al volver a abrirse retoma los que siguen vivos.

## Compilar e instalar

Requiere macOS 15 o posterior y Xcode (o las Command Line Tools con Swift 6).

```bash
git clone https://github.com/francofl99/port-deck.git
cd port-deck
./build.sh   # → PortDeck.app
mv PortDeck.app /Applications/
```

`build.sh` firma la app ad hoc. Para firmar con tu propio certificado: `PORTDECK_IDENTITY="Developer ID Application: …" ./build.sh`.

## Archivos

- Proyectos: `~/Library/Application Support/PortDeck/projects.json`
- Logs: `~/Library/Logs/PortDeck/<id>.log`

Los logs se crean con permisos `600` (sólo tu usuario), porque la salida de un servidor de desarrollo puede incluir credenciales.

## Seguridad

PortDeck corre con tus permisos de usuario y sin sandbox, porque su trabajo es lanzar procesos:

- Ejecuta tal cual el comando que configurás para cada proyecto. No agregues proyectos ni importes un `projects.json` de origen desconocido.
- Al abrirse lee el entorno de tu shell interactivo (`$SHELL -ilc env`) y se lo pasa a los procesos que lanza. Eso incluye las variables que exportes en `.zshrc`, tokens incluidos; no las guarda ni las manda a ningún lado.
- Para ver qué puertos están ocupados usa `lsof`, que sin root sólo ve tus propios procesos.
- No hace conexiones de red propias.

Para reportar una vulnerabilidad, ver [SECURITY.md](SECURITY.md).

## Licencia

[MIT](LICENSE)
