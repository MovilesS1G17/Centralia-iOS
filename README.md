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

Bearer tokens are stored in the iOS Keychain. Profile name edits use the live API; changing an email address or password remains unavailable until its verified email flow is implemented. The remaining library/profile repositories are mock-backed until their backend endpoints are implemented.
