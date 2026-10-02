# Centralia iOS

Native SwiftUI frontend for Centralia, built for the **ISIS3510 Mobile Apps Development** course at _Universidad de los Andes_. Centralia organizes short-form videos saved from TikTok, Instagram Reels, and YouTube Shorts.

## V3 backend configuration

The live dependency container uses the V3 API for authentication, profile, library, folders, search history, and import stages. The endpoint and payload inventory is in [API_CONTRACT_V3.md](API_CONTRACT_V3.md). Start the backend from `../Centralia-Backend`:

```sh
docker compose up -d db
uv run alembic upgrade head
uv run uvicorn app.main:app --reload
```

Set `CENTRALIA_API_BASE_URL` in the Xcode scheme's Run environment variables or set `CentraliaAPIBaseURL` in `Centralia/Info.plist`. Use the origin only, such as `http://127.0.0.1:8000` for the Simulator or a reachable LAN address for a device. The app has no default localhost address; missing or invalid configuration produces a readable error. Production deployments must use HTTPS.

Bearer tokens are stored in the iOS Keychain. Registration requires email verification before a session exists.
