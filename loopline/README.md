# Loopline

Loopline is a Flutter app with a local Dart API server for live exchange rates.

## Run locally

Start the API server from the project root:

```sh
dart run lib/backend/server.dart
```

By default it listens on port `8000`. Check `http://127.0.0.1:8000/health` (or
`/`) for `{"status":"ok"}`. Then run the Flutter app:

```sh
flutter run
```

The iOS simulator uses `127.0.0.1:8000` to reach the server on the Mac. Android
emulator builds use `10.0.2.2:8000`. For a different address, pass
`--dart-define=API_URL=http://<host>:<port>` when running Flutter. The server
port can be changed with the `PORT` environment variable.
