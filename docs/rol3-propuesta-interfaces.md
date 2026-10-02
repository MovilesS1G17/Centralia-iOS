# Rol 3: propuesta de interfaces para el Rol 1

Propuesta de firmas Swift para los repositorios y el tracker de analítica que consume la biblioteca de videos, alineadas con el contrato del backend V3. Es solo un documento: no hay código del Rol 1 modificado.

## Convenciones del contrato V3

- Rutas bajo `/v1`, JSON en camelCase (`sourceURL`, `folderID`, `savedAt`, `thumbnailURL`, `embedURL`, `symbolName`).
- `Authorization: Bearer <token>` en todo, salvo `/v1/streams/{id}` (firmado) y `POST /v1/analytics/events` (Bearer opcional).
- Header `X-Client-Platform: ios` en todas las llamadas.
- Errores: `{"code": "...", "detail": "...", ...extra}`. `detail` es apto para mostrar al usuario y `code` es estable para ramificar. Campos extra, por ejemplo `retryAfter`.
- El backend no tiene endpoint de búsqueda ni de tags. Ambos se resuelven en el cliente a partir de `GET /v1/videos`.

## Error compartido

El Rol 1 ya expone `APIClientError` (`.server(status:code:detail:email:retryAfter:)`, `.sessionExpired`, `.networkUnavailable`, `.invalidResponse`). Features lo consume sin duplicarlo: `FeatureError` usa `detail` como mensaje y `code` para ramificar y para `error_shown`. `CodedError` (en `Features/Shared/FeatureError.swift`) solo cubre errores locales o de prueba que no vienen de `APIClient`.

Un 401 llega como `.sessionExpired` (el Rol 2 cierra la sesión) y se reporta como `not_authenticated`.

## VideoItemRepository

```swift
enum LibraryFolderScope: Equatable, Sendable {
    case all
    case unorganized
    case folder(UUID)
}

/// Solo las llaves presentes cambian. `.some(nil)` en folderID mueve a Unorganized.
struct VideoUpdate: Equatable, Sendable {
    var folderID: UUID??
    var note: String??
    var tags: [String]?
    var customTitle: String??
}

struct VideoPlayback: Equatable, Sendable {
    let streamURL: URL?      // ruta firmada ya resuelta contra la base URL
    let streamReady: Bool
    let expiresAt: Date?
    let embedURL: URL?
}

protocol VideoItemRepository {
    func videos(in scope: LibraryFolderScope) async throws -> [VideoItem]
    func video(id: UUID) async throws -> VideoItem
    func createVideo(_ video: VideoItem) async throws -> VideoItem
    func updateVideo(id: UUID, changes: VideoUpdate) async throws -> VideoItem
    func deleteVideo(id: UUID) async throws
    func restoreVideo(id: UUID) async throws -> VideoItem
    func playback(for id: UUID) async throws -> VideoPlayback
}
```

| Método | Endpoint | Body / query | Errores (`code`) |
|---|---|---|---|
| `videos(in:)` | `GET /v1/videos?folder=all\|unorganized\|<uuid>` | Query `folder` | `not_authenticated` (401), `validation_error` (422) |
| `video(id:)` | `GET /v1/videos/{id}` | | `video_not_found` (404) |
| `createVideo` | `POST /v1/videos` | `id`, `sourceURL`, `platform`, `creator`, `durationSeconds`, `sourceCaption`, `transcript`, `extractedOnScreenText`, `generatedSummary`, `customTitle`, `folderID`, `tags`, `note`, `analysisStatus` | `duplicate_video` (409), `folder_not_found` (404), `invalid_url`, `unsupported_source`, `unsupported_youtube_video`, `unsupported_instagram_post` (422), `validation_error` (422) |
| `updateVideo` | `PATCH /v1/videos/{id}` | Solo las llaves de `VideoUpdate` presentes | `video_not_found` (404), `folder_not_found` (404), `validation_error` (422) |
| `deleteVideo` | `DELETE /v1/videos/{id}` | | `video_not_found` (404) |
| `restoreVideo` | `POST /v1/videos/{id}/restore` | | `video_not_found` (404) |
| `playback(for:)` | `GET /v1/videos/{id}/playback` | | `video_not_found` (404) |

Notas:
- `VideoItem` no tiene `thumbnailURL` ni `embedURL`. Si se quieren mostrar, el Rol 1 debe agregarlos al modelo global (campos opcionales).
- `VideoPlayback` y `VideoPlaybackRepository.playback(for:)` ya existen en Domain (Rol 1); aquí solo se listan para completar el contrato.
- Hoy `moveVideo`, `updateNote` y `updateTags` son tres llamadas. Todas se pueden implementar sobre `updateVideo`; para no romper a los consumidores se pueden dejar como extensión del protocolo.
- `restoreVideo(id:)` devuelve el video porque el backend responde `VideoOut`. Si el borrado fue de la carpeta, vuelve a Unorganized.
- El servidor normaliza `tags` (recorta, quita duplicados sin importar mayúsculas, máximo 60 caracteres) y devuelve el resultado. El cliente debe usar el video devuelto, no su copia local.
- `GET /v1/streams/{id}?expires&signature` no necesita repositorio: `VideoPlayback.streamURL` ya trae la URL completa.

## FolderRepository

```swift
protocol FolderRepository {
    func folders() async throws -> [LibraryFolder]
    func createFolder(named name: String, symbolName: String) async throws -> LibraryFolder
    func renameFolder(id: UUID, to name: String) async throws -> LibraryFolder
    func deleteFolder(id: UUID) async throws
}
```

| Método | Endpoint | Body | Errores (`code`) |
|---|---|---|---|
| `folders()` | `GET /v1/folders` | | `not_authenticated` |
| `createFolder` | `POST /v1/folders` | `name`, `symbolName` | `folder_name_empty` (422), `folder_name_duplicate` (409) |
| `renameFolder` | `PATCH /v1/folders/{id}` | `name` | `folder_not_found` (404), `folder_name_empty` (422), `folder_name_duplicate` (409) |
| `deleteFolder` | `DELETE /v1/folders/{id}` | | `folder_not_found` (404) |

Notas:
- La lista llega ordenada por nombre sin distinguir mayúsculas.
- Un `symbolName` que el servidor no conoce se guarda como `folder`.
- Al borrar una carpeta, sus videos pasan a Unorganized (no se borran).
- La firma coincide con la actual, así que no hay cambios para los consumidores.

## SearchHistoryRepository

```swift
protocol SearchHistoryRepository {
    func recentSearches() async throws -> [String]
    func recordSearch(_ query: String) async throws
    func clearSearchHistory() async throws
}
```

| Método | Endpoint | Detalle | Errores (`code`) |
|---|---|---|---|
| `recentSearches()` | `GET /v1/search-history` | `[String]`, máximo 8, más reciente primero | `not_authenticated` |
| `recordSearch(_:)` | `POST /v1/search-history` | `{ "query": String }` (máximo 200 caracteres). Responde 204. | `validation_error` (422) |
| `clearSearchHistory()` | `DELETE /v1/search-history` | 204 | `not_authenticated` |

Notas:
- El servidor mueve la consulta al tope y quita duplicados sin importar mayúsculas. Un texto vacío se ignora.
- `POST /v1/search-history` ya registra `search_performed` en el servidor, así que el cliente no debe enviar ese evento.
- La firma coincide con la actual. Solo falta reemplazar `MockSearchHistoryRepository` en `live()`.

## VideoImportPipeline (consumido por Save)

```swift
protocol VideoImportPipeline {
    func detectPlatform(from sourceURL: URL) async throws -> VideoPlatform
    func extractMetadata(from sourceURL: URL, platform: VideoPlatform) async throws -> ImportedVideoMetadata
    func generateTags(for metadata: ImportedVideoMetadata) async throws -> [String]
    func suggestFolder(for metadata: ImportedVideoMetadata, tags: [String]) async throws -> String?
}
```

| Método | Endpoint | Errores (`code`) |
|---|---|---|
| `detectPlatform` | `POST /v1/imports/detect` `{sourceURL}` | `invalid_url`, `unsupported_source`, `unsupported_youtube_video`, `unsupported_instagram_post` (todos 422) |
| `extractMetadata` | `POST /v1/imports/metadata` `{sourceURL}` | los mismos que `detect` |
| `generateTags` | `POST /v1/imports/tags` `{metadata}` → `{tags}` | `validation_error` |
| `suggestFolder` | `POST /v1/imports/folder-suggestion` `{metadata, tags}` → `{folderName}` | `validation_error` |

La firma coincide con la actual. Hoy `detectPlatform` es local y `generateTags`/`suggestFolder` devuelven vacío: deben pasar a llamar al backend.

## Analítica

El Rol 1 define `AnalyticsRepository.record(_:)` con `ClientAnalyticsEvent` (`name`, `occurredAt`, `properties: [String: AnalyticsValue]`). Features construye los eventos sobre ese tipo (`Features/Shared/AnalyticsTracking.swift`) y depende de un protocolo mínimo, fire-and-forget:

```swift
protocol AnalyticsTracking: Sendable {
    func track(_ event: ClientAnalyticsEvent)    // nunca lanza ni bloquea
}
```

Hoy los ViewModels usan `NoOpAnalyticsTracking`. Para activarlo falta un adaptador de `AnalyticsTracking` sobre `AnalyticsRepository` (con buffer y reintento) y pasarlo desde `DependencyContainer`/`AuthenticatedAppView`.

Endpoint: `POST /v1/analytics/events`

```json
{ "events": [ { "name": "screen_viewed", "occurredAt": "2026-10-02T12:00:00Z", "properties": { "screen": "library" } } ] }
```

- Respuesta: 202 `{ "accepted": Int, "rejected": Int }`. Máximo 100 eventos por llamada.
- Bearer opcional. Si hay sesión el evento se asocia al usuario.
- `occurredAt` es opcional. Si queda fuera de la ventana de 7 días o 5 minutos a futuro, el servidor usa la hora de llegada.
- Se recomienda un buffer con envío por lotes y reintento simple. Un fallo no debe llegar a la UI.

Eventos de Rol 3 (`play_started` y `share_tapped` están definidos pero todavía no se emiten: el primero espera el playback real de `/v1/videos/{id}/playback` y el segundo un punto de captura confiable en la hoja de compartir. `play_failed` se emite hoy solo cuando no se puede abrir el enlace original, con `reason` = `open_failed`):

| Evento | Propiedades |
|---|---|
| `screen_viewed` | `screen`: `library`, `search`, `video_detail`, `folders`, `folder_detail`, `save_video` |
| `error_shown` | `screen`, `code` |
| `play_started` | `video_id`, `video_platform` |
| `play_failed` | `video_id`, `video_platform`, `reason` |
| `share_tapped` | `video_id` |

El servidor rechaza los eventos que él mismo registra: `video_saved`, `video_opened`, `video_updated`, `video_deleted`, `video_restored`, `search_performed`, `playback_requested`, `link_checked`, `metadata_extracted`, `tags_suggested`, `folder_suggested`, `api_request` y los de autenticación. El cliente no debe enviarlos.

## Códigos de error que maneja la biblioteca

| `code` | HTTP | Dónde aparece |
|---|---|---|
| `not_authenticated` | 401 | Cualquier llamada con sesión |
| `video_not_found` | 404 | get, update, delete, restore, playback |
| `folder_not_found` | 404 | create/update de video, rename/delete de carpeta |
| `duplicate_video` | 409 | create de video |
| `folder_name_empty` | 422 | create/rename de carpeta |
| `folder_name_duplicate` | 409 | create/rename de carpeta |
| `unsupported_source` | 422 | create de video, detect, metadata |
| `invalid_url` | 422 | detect, metadata |
| `unsupported_youtube_video` | 422 | detect, metadata |
| `unsupported_instagram_post` | 422 | detect, metadata |
| `stream_link_expired` | 403 | stream |
| `stream_unavailable` | 502 | stream |
| `validation_error` | 422 | cualquier body o query inválido |

## Lo que se necesita del Rol 1

1. Confirmar que los repositorios de biblioteca usan el `APIClient` nuevo (`/v1`, camelCase, `X-Client-Platform`) y que sus errores llegan como `APIClientError`.
2. DTOs compartidos para `VideoItem` y `LibraryFolder`.
3. Las firmas de este documento (en especial `updateVideo`, `restoreVideo(id:)`, `playback` y `videos(in:)`).
4. Un adaptador `AnalyticsTracking` sobre `AnalyticsRepository` y su inyección en `DependencyContainer`/`AuthenticatedAppView`.
5. `SearchHistoryRepository` e imports apuntando al backend en `live()`.
6. Decidir si `VideoItem` incorpora `thumbnailURL` y `embedURL`.

Mientras tanto, los repositorios actuales siguen funcionando con los mocks y Features compila contra las firmas vigentes.
