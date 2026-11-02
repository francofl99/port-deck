# PortDeck

**English** · [Español](README.es.md)

A macOS menu bar app that starts, stops and watches the projects you run on localhost. The interface is in Spanish.

- **Menu:** every project with its port and status (running, starting, stopped, port taken by another process, failed). Start, stop, open in the browser, start on another port and view the log.
- **Window:** add, edit and remove projects. When you pick a folder it suggests a command based on what it finds (`package.json`, `artisan`, `manage.py`, `compose.yaml`).
- **Login:** opens at login (System Settings → Login Items) and can start the projects you mark.

## How each project starts

The command runs with `zsh -c` inside the project folder, with your interactive shell's environment (nvm, Homebrew and the rest of your PATH). `{PORT}` is replaced with the chosen port, and `$PORT` is exported too:

```text
npm run dev -- --port {PORT}
php artisan serve --port={PORT}
npm start                      # if the app reads $PORT
```

Starting on another port only works if the command uses `{PORT}` or the app honors `$PORT`.

Each project runs in its own process group: stopping it sends `SIGTERM` to the whole group, then `SIGKILL` after 5 s if it is still alive. If PortDeck quits without stopping them, it picks the live ones back up when it reopens; it recognizes each one by the pid and start time of its main process, so it never adopts an unrelated process that reused the same pid.

## Build and install

Requires macOS 15 or later and Xcode (or the Command Line Tools with Swift 6).

```bash
git clone https://github.com/francofl99/port-deck.git
cd port-deck
./build.sh   # → PortDeck.app
mv PortDeck.app /Applications/
```

`build.sh` signs the app ad hoc. To sign with your own certificate: `PORTDECK_IDENTITY="Developer ID Application: …" ./build.sh`.

## Files

- Projects: `~/Library/Application Support/PortDeck/projects.json`
- Logs: `~/Library/Logs/PortDeck/<id>.log`

Logs are created with mode `600` (your user only), because dev server output can include credentials.

## Security

PortDeck runs with your user's permissions and without a sandbox, because its job is to launch processes:

- It runs the command you configure for each project as is. Don't add projects or import a `projects.json` from an unknown source.
- On launch it reads your interactive shell's environment (`$SHELL -ilc env`) and passes it to the processes it starts. That includes the variables you export in `.zshrc`, tokens included; it neither stores them nor sends them anywhere.
- To see which ports are taken it uses `lsof`, which without root only sees your own processes.
- It makes no network connections of its own.

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
