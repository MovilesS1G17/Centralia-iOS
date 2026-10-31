# Sprint 3 · Concurrencia, almacenamiento local, caché y conectividad eventual

Centralia guarda shorts de TikTok, Instagram y YouTube en una biblioteca con carpetas, tags y notas. En el Sprint 3 las dos apps pasan a ser **offline-first**: la biblioteca abre sin conexión, los cambios hechos offline se aplican al instante y se sincronizan solos cuando vuelve la red, y lo que de verdad necesita el servidor lo dice con un mensaje claro.

Equipo: **Android** (Kotlin / Compose): Enrique, Alex · **iOS** (SwiftUI): David, Alejandro, Gustavo · **Backend** (FastAPI): compartido.

## 1. Tabla por integrante

| Integrante | App | BQ nueva (Sprint 3) | Tipo | Estrategia que implementa | Dónde está |
|---|---|---|---|---|---|
| David | iOS | BQ6 (Sprint 1 #2): ¿Cuánto tarda en cargar la biblioteca y cómo varía entre dispositivos? | 1 | **Multithreading**: `async let` para cargar videos y carpetas en paralelo; `actor`s para el disco y la sincronización; colas GCD en segundo plano para `NWPathMonitor` y para decodificar portadas | `Data/Offline/SyncManager.swift`, `ConnectivityMonitor.swift`, `Shared/Components/CoverImageLoader.swift`, `LibraryViewModel` / `SearchViewModel` |
| Enrique | Android | BQ7 (Sprint 1 #9): ¿La plataforma de origen influye en la probabilidad de volver a abrir un short? | 3 | **Multithreading + caché**: corrutinas (`async`/`await` en `coroutineScope`, `Dispatchers.IO`, scope con `SupervisorJob`, `Mutex`); `LruCache` de reproducción y caché de memoria + disco de Coil para portadas | `data/offline/SyncManager.kt`, `data/local/LibraryMemoryCache.kt`, `CentraliaApplication.kt`, `LibraryViewModel` / `SearchViewModel` |
| Alejandro | iOS | BQ8 (Sprint 1 #7): ¿Organizar con carpetas o tags hace que se vuelva a abrir más lo guardado? | 3 | **Almacenamiento local**: copia de la biblioteca en JSON (Application Support), outbox de cambios pendientes en JSON y perfil / búsquedas en `UserDefaults` | `Data/Local/LocalLibraryStore.swift`, `PendingActionQueue.swift`, `PendingAction.swift`, `Data/Offline/OfflineProfileRepositories.swift` |
| Gustavo | iOS | BQ9 (Sprint 1 #14): ¿Cómo afecta el tiempo de respuesta de la búsqueda a la capacidad de reabrir lo guardado? | 5 | **Caché + conectividad eventual**: `NSCache` de reproducción con TTL de 10 min; portadas con `NSCache` + `URLCache` de 100 MB; repositorio offline-first y banner | `Data/Local/LibraryMemoryCache.swift`, `Data/Offline/OfflineFirstLibraryRepository.swift`, `Shared/Components/OfflineBanner.swift` |
| Alex | Android | BQ10 (Sprint 1 #8): ¿Los usuarios crean carpetas y mueven shorts a mano lo suficiente para justificar auto-organización con IA? | 3 | **Almacenamiento local + conectividad eventual**: biblioteca y outbox en JSON (`filesDir/offline`), perfil y búsquedas en `SharedPreferences`; `ConnectivityObserver`, repositorio offline-first y banner | `data/local/LocalLibraryStore.kt`, `PendingActionQueue.kt`, `data/offline/OfflineFirstLibraryRepository.kt`, `platform/ConnectivityObserver.kt`, `ui/components/OfflineBanner.kt` |

Rutas de la columna "Dónde está": Android desde `app/src/main/java/com/centralia/app/`, iOS desde `Centralia/`.

Todas las BQ del Sprint 3 salen de la lista entregada en el Sprint 1 (entre paréntesis su número) y son distintas a las del Sprint 2. Tipo 1 = rendimiento de la app; Tipo 3 = uso de features, respondida para el equipo en el dashboard (no se le muestra al usuario, por eso no es Tipo 2); Tipo 5 = cruza rendimiento con comportamiento. Las BQ del Sprint 2 (1–5) siguen en el dashboard; las del Sprint 3 (6–10) tienen su propia fila de métricas ("Sprint 3").

## 2. Features de la app

| Feature | Qué hace |
|---|---|
| Guardar un short | Pega el link; el backend detecta la plataforma, extrae metadatos, sugiere tags y carpeta |
| Biblioteca, búsqueda y carpetas | Lista, filtra y organiza los shorts guardados |
| Detalle y reproducción | Reproductor nativo con el MP4 del backend, embed web como respaldo |
| Context-aware: ahorro de datos | Con datos móviles el backend omite el MP4 y la app muestra el aviso |
| Sensor: shake to undo | Tras borrar, sacudir el teléfono deshace el borrado (acelerómetro) |
| Smart folder | Tarjeta "Smart suggestion" en Guardar con la carpeta sugerida |
| **Nuevo: modo offline** | Biblioteca sin conexión, cambios en cola, banner de estado y sincronización automática |

## 3. Business questions del Sprint 3

| BQ | Sprint 1 | Integrante | Tipo | Pregunta | Por qué importa | Eventos |
|---|---|---|---|---|---|---|
| 6 | #2 | David | 1 | ¿Cuánto tarda en cargar la biblioteca y cómo varía entre dispositivos? | La biblioteca es la primera pantalla; si tarda, el usuario abandona. Muestra si iOS o Android necesitan optimización y si se cumple el escenario de calidad de 2 s | `api_request` de `GET /v1/videos` y `GET /v1/folders`, por app |
| 7 | #9 | Enrique | 3 | ¿La plataforma de origen influye en volver a abrir un short? | Dice en qué plataforma enfocar mejoras de importación y reproducción | `video_saved.video_platform` + reproducciones 30 min–7 días después |
| 8 | #7 | Alejandro | 3 | ¿Organizar con carpetas o tags aumenta las reaperturas? | Valida la propuesta de valor: si organizar ayuda a recuperar, vale la pena empujar al usuario a organizar | `video_saved` (carpeta, tags) + `video_updated` + reaperturas |
| 9 | #14 | Gustavo | 5 | ¿Cómo afecta el tiempo de búsqueda a reabrir lo guardado? | Conecta rendimiento con comportamiento: si la búsqueda lenta reduce reaperturas, optimizarla tiene impacto directo | Latencia de búsqueda por usuario (BQ1) + reaperturas |
| 10 | #8 | Alex | 3 | ¿Se organiza a mano lo suficiente para justificar auto-organización con IA? | Decide si construir la feature premium de IA (regla: 1 o más acciones manuales por usuario por semana) | `POST /v1/folders` + `video_updated` con `folder` |

Se responden en `app/analytics/business.py`, en `GET /v1/analytics/business-questions` y en el dashboard (una métrica por pregunta).

## 4. Estrategias por app (dónde y por qué)

### Multithreading / concurrencia

| | Android | iOS |
|---|---|---|
| Cargas en paralelo | `coroutineScope { async {…} }` pide videos y carpetas a la vez en Library y Search | `async let` en Library y Search (igual que el resto de pantallas) |
| Trabajo en segundo plano | Scope de la app `SupervisorJob() + Dispatchers.IO`: escritura a disco y sincronización nunca bloquean el hilo principal (evita ANR) | `actor` para disco, outbox y sincronización; `Task(priority: .utility)` para sincronizar |
| Exclusión mutua | `Mutex` en `SyncManager`, `LocalLibraryStore` y `PendingActionQueue` | Los `actor` serializan el acceso; `isSyncing` evita dos sincronizaciones a la vez |
| Volver a la UI | `withContext(Dispatchers.Main)` al terminar de sincronizar | `DispatchQueue.main.async` desde la cola de `NWPathMonitor`; `@MainActor` para el estado de la UI |
| Otros | `ConnectivityManager` avisa por callback | Portadas decodificadas en `DispatchQueue.global(qos: .userInitiated)` |

### Almacenamiento local

| Qué | Android | iOS | Por qué |
|---|---|---|---|
| Copia de la biblioteca (videos + carpetas) | `files/offline/library.json` (kotlinx.serialization, escritura atómica) | `Application Support/offline/library.json` (Codable, escritura atómica y cifrada) | Es estructurada y grande: un archivo JSON es simple y suficiente; no hace falta una base de datos local |
| Cambios pendientes (outbox) | `files/offline/outbox.json` | `Application Support/offline/outbox.json` | Deben sobrevivir a cerrar la app o reiniciar el teléfono |
| Perfil y búsquedas recientes | `SharedPreferences` | `UserDefaults` | Son pocos datos, clave-valor |

Al cerrar sesión se borra todo lo anterior (y las cachés).

### Caché

| Qué | Android | iOS | Política |
|---|---|---|---|
| Biblioteca en memoria | `LibraryMemoryCache` (`@Volatile`) | `LibraryMemoryCache` | Evita releer el archivo al moverse entre pantallas offline |
| Respuesta de reproducción | `LruCache` de 32, 10 min | `NSCache` de 32, 10 min | La llave incluye la red, porque con datos móviles el backend responde distinto. El link firmado dura 6 h, así que 10 min es seguro |
| Portadas | Coil: memoria 20 % + disco 100 MB (`cacheDir/covers`) | `NSCache` + `URLCache` 100 MB (`Caches/covers`) | Cache falling back to network: una portada vista una vez se ve offline |

### Conectividad eventual por funcionalidad

| Funcionalidad | Estrategia | Sin conexión |
|---|---|---|
| Biblioteca, carpetas, búsqueda | Network falling back to cache (memoria → disco) | Muestra la copia guardada y el banner "You're offline. Showing your saved library." |
| Borrar, deshacer (shake/botón), mover, tags, nota | Local primero + cola (outbox) que se sincroniza al volver la red | Se aplica al instante, se cuenta en el banner y se envía con `X-Queued-At` |
| Reproducir | Cache falling back to network (10 min) | Si no está en caché: "You're offline. Playing a short needs a connection…" |
| Portadas | Cache falling back to network | Las ya vistas se muestran; las demás conservan el color de la tarjeta |
| Guardar un short, crear / renombrar / borrar carpeta | Network only | Mensaje "… needs a connection. Try again when you're back online." |
| Búsquedas recientes | Network falling back to cache | Las nuevas búsquedas se guardan localmente |
| Perfil | Network falling back to cache; editar es network only | Muestra el último perfil; cambios piden conexión |
| Iniciar sesión, registro, código, reset | Network only | Mensaje de error de conexión (iOS: "We couldn't reach Centralia…", Android: "Centralia can't reach the server…") |

## 5. Escenarios de conectividad eventual

| # | Escenario | Comportamiento esperado |
|---|---|---|
| 1 | Abrir la app en modo avión | Abre la biblioteca guardada, con portadas vistas, y el banner offline |
| 2 | Borrar un short offline y sacudir para deshacer | El borrado y el undo se cancelan entre sí en la cola: no se envía nada |
| 3 | Cambiar tags y carpeta offline, luego volver a Wi-Fi | El banner pasa a "Back online · syncing 2 changes…", se envían en orden y las listas se recargan con la versión del servidor |
| 4 | Editar la nota dos veces offline | Solo se envía la última versión |
| 5 | Intentar guardar un short offline | Mensaje claro; nada queda a medias |
| 6 | La red se cae a mitad de la sincronización | Se detiene y conserva el resto para el próximo intento |
| 7 | Un cambio offline sobre un short borrado en otro teléfono (404) | El cambio se descarta para no bloquear la cola |
| 8 | Reabrir un short visto hace menos de 10 min | Se reproduce sin pedir `/playback` otra vez |
| 9 | Cerrar sesión | Se borran la copia local, la cola y las cachés |

## 6. Justificación cruzada (mismo equipo)

Cada integrante revisa y justifica las estrategias de sus compañeros de plataforma. Esta sección la debe escribir cada uno con sus propias palabras; los puntos de partida son:

- **Android: Enrique sobre Alex**: por qué JSON en archivos para la biblioteca y `SharedPreferences` para datos clave-valor; por qué la cola debe persistir en disco.
- **Android: Alex sobre Enrique**: por qué corrutinas en `Dispatchers.IO` evitan ANRs; por qué `LruCache` con TTL y la red en la llave.
- **iOS: David sobre Alejandro y Gustavo**: por qué `actor` para el disco; por qué `NSCache` (se vacía sola con poca memoria) y `URLCache` para portadas.
- **iOS: Alejandro sobre David y Gustavo**: por qué `async let` y colas GCD en segundo plano; por qué cache falling back to network en reproducción.
- **iOS: Gustavo sobre David y Alejandro**: por qué la sincronización corre en un `actor` fuera de las pantallas; por qué la cola persiste en Application Support.

## 7. Resultados de las pruebas (iOS)

Probado por Gustavo en Xcode 27.1 y en un iPhone real, con el backend local en Docker. Solo se marca como aprobado lo que se probó de verdad.

### Compilación y pruebas automáticas

| Prueba | Resultado |
|---|---|
| Compilación (⌘B) | Compila |
| Unit tests (`CentraliaTests`) | 146 en total: 142 pasan, 4 fallan |
| UI tests (`CentraliaUITests`) | 11 en total: 9 fallan porque necesitan una sesión iniciada; no se cuentan como prueba del Sprint 3 |

Las pruebas nuevas del Sprint 3 (cola de cambios, almacenamiento local, caché de reproducción, headers `X-Queued-At` y `X-Undo-Method`, reglas de fallo de la sincronización y `BatchingAnalyticsTracker`) pasan todas.

Los 4 unit tests que fallan vienen de sprints anteriores y quedan pendientes:

| Test | Motivo |
|---|---|
| `searchDoesNotClaimTranscriptOrCaptionMatching` | Espera que la búsqueda no use transcripción ni caption, pero la búsqueda del Sprint 2 sí los incluye |
| `httpToTheInternetIsRejectedEvenWhenLocalHTTPIsOn` | `PlaybackURLPolicy` toma `192.168.1.10.example.com` como host local |
| `smartFolderSuggestionCreatesAndSelectsAMissingFolder` | Sugerencia de carpeta inteligente, pendiente de revisar |
| `offersToCreateAMissingFolderWithAFittingIcon` | Sugerencia de carpeta inteligente, pendiente de revisar |

### Escenarios de conectividad en el iPhone

| # | Escenario | Resultado |
|---|---|---|
| 1 | Abrir la app en modo avión | Aprobado: biblioteca guardada, portadas vistas y banner offline |
| 2 | Borrar offline y sacudir para deshacer | No probado |
| 3 | Cambiar tags y carpeta offline y volver a Wi-Fi | Aprobado: los cambios se aplican al instante, se cuentan en el banner y llegan al servidor al volver la red. El aviso "syncing" dura menos de un segundo y no se alcanzó a ver |
| 4 | Editar la nota dos veces offline | No probado |
| 5 | Intentar guardar un short offline | Aprobado: mensaje claro de que necesita conexión |
| 6 | La red se cae a mitad de la sincronización | No probado |
| 7 | Cambio offline sobre un short borrado en otro teléfono | No probado (requiere un segundo dispositivo) |
| 8 | Reabrir un short visto hace menos de 10 min | Aprobado: se reproduce sin volver a cargar |
| 9 | Cerrar sesión | No probado |
