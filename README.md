# Centralia iOS

Native SwiftUI frontend for Centralia, built for the **ISIS3510 Mobile Apps Development** course at _Universidad de los Andes_. Centralia organizes short-form videos saved from TikTok, Instagram Reels, and YouTube Shorts.

## Local authentication backend

The app uses the Centralia backend for Member 1's email registration, login, session restoration, `GET /me`, `PATCH /me` for the display name, and sign-out. Start the backend first from `../Centralia-Backend`:

```sh
docker compose up -d db
uv run alembic upgrade head
uv run uvicorn app.main:app --reload
```

By default, the simulator connects to `http://127.0.0.1:8000`. To use a different backend address, set `CENTRALIA_API_BASE_URL` in the Xcode scheme's Run environment variables (for example, a Mac LAN IP when testing on a physical device). Production deployments must use HTTPS.

Bearer tokens are stored in the iOS Keychain. Profile name edits use the live API; changing an email address or password remains unavailable until its verified email flow is implemented. Library and folder operations use the live API; unrelated search history and profile features still use their existing local implementations.

## Live Sprint 2 library

The app's live dependency container now uses the backend for saving videos, folders, library/detail reads and edits. The login token stays in Keychain. Configure `CentraliaAPIBaseURL` in `Centralia/Info.plist` or `CENTRALIA_API_BASE_URL` for the API host; the default loopback address is for the iOS Simulator only. The import preview uses real metadata when the backend provider can supply it and displays unavailable fields without fixture content. Opening an original source records `source_opened` after iOS accepts the URL.
