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

## Compilar

Requiere macOS 15 o posterior y Xcode.

```bash
./build.sh   # → PortDeck.app
```

## Archivos

- Proyectos: `~/Library/Application Support/PortDeck/projects.json`
- Logs: `~/Library/Logs/PortDeck/<id>.log`
