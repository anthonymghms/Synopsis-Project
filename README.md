# Synopsis-Project
This repository contains the work for our Synopsis Project.

## Running locally

The Flutter web app reads Gospel topics and Bible text from the Flask backend.
The backend URL is selected at Flutter build/run time with `API_BASE_URL`, so
`gospel_frontend/lib/main.dart` does not need to be edited when switching
between local development and VPS deployment.

### Start Flask locally

From the repository root:

```sh
python3 app.py
```

The local backend listens on:

```text
http://127.0.0.1:8010
```

`serviceAccountKey.json` must exist locally for Firebase Admin SDK access. It is
ignored by git and should not be committed.

### Run Flutter locally

From the Flutter project directory:

```sh
cd gospel_frontend
flutter run -d chrome --web-port 8760 --dart-define=API_BASE_URL=http://127.0.0.1:8010
```

If `API_BASE_URL` is omitted, the app defaults to `http://127.0.0.1:8010`.

## Building for VPS

From the Flutter project directory:

```sh
cd gospel_frontend
flutter build web --release --dart-define=API_BASE_URL=http://164.68.108.181:8010
```

Deploy the generated `gospel_frontend/build/web` files to the VPS frontend host.
The Flask backend should keep serving the existing API routes:

```text
/topics
/get_verse
/get_chapter
```

Serve the Flutter build with Nginx or another static server rather than
`flutter run`. Enable compression and long-lived caching for hashed Flutter
assets:

```nginx
gzip on;
gzip_types text/css application/javascript application/json application/wasm;

location / {
  try_files $uri $uri/ /index.html;
}

location ~* \.(?:js|css|wasm|png|jpg|jpeg|gif|svg|ico)$ {
  expires 30d;
  add_header Cache-Control "public, immutable";
}

location = /index.html {
  add_header Cache-Control "no-cache";
}
```

Run Flask behind a production WSGI server such as gunicorn, and keep debug mode
off unless explicitly testing:

```sh
gunicorn -w 2 -b 0.0.0.0:8010 app:app
```

For local Flask debugging, opt in with:

```sh
FLASK_DEBUG=1 python3 app.py
```

## Backend CORS

`app.py` allows the local Flutter web dev origin and the current VPS frontend
origin by default. If the frontend moves to another host, set a comma-separated
`CORS_ORIGINS` environment variable before starting Flask, for example:

```sh
CORS_ORIGINS=http://localhost:8760,http://164.68.108.181 python3 app.py
```
