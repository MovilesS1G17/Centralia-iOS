# Centralia V3 API contract for iOS

Backend references: `../Centralia-Backend/app/routers/`, `app/schemas.py`, and `app/errors.py`. The base URL is the origin, without `/v1`.

Every request sends `Accept: application/json` and `X-Client-Platform: ios`. JSON bodies send `Content-Type: application/json`. Protected routes send `Authorization: Bearer <accessToken>`. A 204 response has no body. Error bodies use `{"code":"stable_code","detail":"displayable text"}` and may add `email` or `retryAfter`.

| Method and path | Request JSON | Success | Important errors |
| --- | --- | --- | --- |
| POST `/v1/auth/register` | `email`, `password` | 202 `status`, `email`, `resendAvailableIn`; no token | 409 `account_already_exists`; 422 validation; 503 email |
| POST `/v1/auth/verify-email` | `email`, `code` | 200 `accessToken`, `tokenType`, `user` | 400 `invalid_code`/`code_expired`; 429 attempts |
| POST `/v1/auth/verification-code` | `email` | 202 pending verification | 429 `code_resend_too_soon` |
| POST `/v1/auth/login` | `email`, `password` | 200 session | 401 `invalid_credentials`; 403 `email_not_verified` with `email`, `retryAfter`; 429 `account_locked` |
| POST `/v1/auth/password-reset` | `email` | 202 `status`, `resendAvailableIn` | 422 validation; 503 email |
| POST `/v1/auth/password-reset/confirm` | `email`, `code`, `newPassword` | 200 session | 400/429 code; 422 password |
| POST `/v1/auth/logout` | none, Bearer | 204 | 401 session |
| POST `/v1/auth/logout-all` | none, Bearer | 204 | 401 session |
| GET `/v1/me` | Bearer | 200 `id`, `displayName`, `email`, `membershipStatus` | 401 session |
| PATCH `/v1/me` | `displayName`, `email` | 200 profile | 409 `email_in_use`; 422 validation |
| POST `/v1/me/password` | `currentPassword`, `newPassword` | 204 | 400 incorrect/unchanged; 422 weak |
| GET `/v1/me/sessions` | Bearer | 200 device session array | 401 session |
| GET/PUT `/v1/me/notification-preferences` | PUT: three camelCase booleans | 200 preferences | 401 session |
| GET `/v1/me/statistics` | Bearer | 200 counts and `platformCounts` | 401 session |
| GET `/v1/me/export` | Bearer | 200 profile, preferences, folders, videos | 401 session |
| GET `/v1/videos` | Optional `folder=all/unorganized/<UUID>` | 200 video array | 401 session |
| POST `/v1/videos` | `id`, `sourceURL`, `platform`, `creator`, `durationSeconds`; optional metadata, folder, tags, note | 201 video | 409 `duplicate_video`; 422 validation |
| GET `/v1/videos/{id}` | Bearer | 200 video; records `video_opened` | 404 `video_not_found` |
| GET `/v1/videos/{id}/playback` | Bearer | 200 `streamURL`, `streamReady`, `expiresAt`, `embedURL` | 404 video |
| GET `/v1/streams/{id}` | Signed path and query from `streamURL`; no Bearer | MP4 with byte ranges | 403 `stream_link_expired`; 404 video |
| PATCH `/v1/videos/{id}` | Any of `folderID`, `note`, `tags`, `customTitle`; null clears | 200 video | 404 video/folder |
| DELETE `/v1/videos/{id}` | Bearer | 204 | 404 video |
| POST `/v1/videos/{id}/restore` | Bearer | 200 video | 404 video |
| GET `/v1/folders` | Bearer | 200 folder array | 401 session |
| POST `/v1/folders` | `name`, `symbolName` | 201 folder | 409 duplicate; 422 empty |
| PATCH `/v1/folders/{id}` | `name` | 200 folder | 404/409/422 |
| DELETE `/v1/folders/{id}` | Bearer | 204 | 404 folder |
| GET `/v1/search-history` | Bearer | 200 string array | 401 session |
| POST `/v1/search-history` | `query` | 204 | 422 validation |
| DELETE `/v1/search-history` | Bearer | 204 | 401 session |
| POST `/v1/imports/detect` | `sourceURL` | 200 `platform` | 422 URL/source |
| POST `/v1/imports/metadata` | `sourceURL`, `platform` | 200 imported metadata | 422 URL/source |
| POST `/v1/imports/tags` | `metadata` | 200 `tags` | 422 validation |
| POST `/v1/imports/folder-suggestion` | `metadata`, `tags` | 200 `folderName` | 422 validation |
| POST `/v1/analytics/events` | `events`: up to 100 `name`, `occurredAt`, scalar `properties` objects | 202 `accepted`, `rejected` | 422 validation |

The backend uses camelCase JSON keys, including `sourceURL`, `folderID`, `savedAt`, and `analysisStatus`. Dates are UTC ISO 8601. `streamURL` is a signed relative path on the API origin and may be null when native streaming is disabled. Registration does not use `displayName`; the name comes from the email until the profile is edited. The backend records domain analytics in its routes. The app sends UI events such as `screen_viewed`, `play_started`, `play_failed`, `share_tapped`, and `error_shown` to `/v1/analytics/events`; server event names are rejected there. Admin analytics report/pipeline routes and `/analytics` dashboard are not used by iOS.

Registration returns `verification_required`. The legacy `createAccount` interface reports that state through `AuthenticationError.verificationRequired`; it does not create a session. Code verification, resend, and password reset confirmation are available through `V3AuthenticationRepository`.
