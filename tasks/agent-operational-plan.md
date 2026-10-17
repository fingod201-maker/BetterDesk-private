# Plan operacyjny: Agent Client + rozbudowa panelu web

**Data:** 2026-04-18
**Kontekst:** Agent client obecnie to 6 plików Rust (rejestracja + sysinfo + stub-czat). Brak zdalnego pulpitu, brak WS do czatu, brak trybu użytkownika vs operatora. Panel web ma `help-requests.ejs` + API oraz slide-over `device-detail` — wymagają rozbudowy.

## Założenia architektoniczne

1. **Agent client = TRAY-FIRST aplikacja.** Menu główne w zasobniku systemowym. Okno GUI otwiera się tylko dla konkretnych funkcji (czat, help-request). Brak głównego sidebara.
2. **Tryby uprawnień:**
   - **User mode** (zwykły użytkownik): "Poproś o pomoc", "Czat", "Pokaż ID".
   - **Admin mode** (OS administrator / root): wszystko powyżej + "Ustawienia", "Zamknij agenta".
   - Detekcja: `IsUserAnAdmin()` (Win32), `geteuid() == 0` (Unix).
3. **Szyfrowanie E2E zachowane** — chat w agencie używa istniejącego `chatCrypto.js` (P-256 ECDH + AES-256-GCM) z panelu web, tylko port Rust.
4. **Kanały komunikacji:**
   - **REST HTTP** — rejestracja, help-request, sysinfo upload (już jest).
   - **WebSocket `/ws/agent/{device_id}`** (NOWE) — chat, powiadomienia, heartbeat, remote session signaling.
   - **Relay TCP/WS** (Faza 4) — video/audio/input dla zdalnego pulpitu.
5. **Bezpieczeństwo:** wszystkie WS z JWT token (z rejestracji), TLS wymagane w produkcji, rate-limit IP, audit log każdej akcji.

---

## Faza 1: Fundament UX + powiadomienia (TA SESJA)

**Cel:** Przeorganizować agent UI + dodać dzwonek powiadomień w panelu web.

### Agent Client
- [x] ~~Obecne okno z sidebarem~~ → **usunięte**. Nowe: minimalne okno "o programie" + pełne menu w trayu.
- [x] Detekcja admina w Rust (`is_os_admin()`).
- [x] Tray menu:
  - **Zawsze:** Pokaż ID | Poproś o pomoc | Czat | Sprawdź połączenie | ───
  - **Admin only:** Ustawienia | Zamknij agenta
  - **Autostart:** domyślnie włączony (już jest)
- [x] Pełny ekran tylko dla: `/chat` (z brandingiem konsoli), `/help` (formularz), `/settings` (tylko admin).
- [x] Rozmiar okna zmniejszony do 480×560 (chat/help/settings), brak rozbudowanego menu bocznego.

### Web panel
- [x] **Dzwonek powiadomień** w navbar (obok `refresh-btn`):
  - Badge z licznikiem nieprzeczytanych help-requestów
  - Dropdown z ostatnimi 10 powiadomieniami
  - Klik → przejście do `/help-requests` + oznaczenie jako przeczytane
- [x] Endpoint `GET /api/bd/notifications` (z filtrem `unread_only`).
- [x] Endpoint `POST /api/bd/notifications/:id/read`.
- [x] Socket.IO event `help-request` już istnieje — podłączyć do dzwonka (real-time).
- [x] i18n klucze `notifications.*` (EN/PL/ZH).

---

## Faza 2: Device Management Modal (NASTĘPNA SESJA)

**Cel:** Zastąpić slide-over `device-detail` pełnoekranowym modalem z rozbudowanym UI inspirowanym nVision, umożliwiającym zdalną inwentaryzację i zarządzanie urządzeniem przez agenta.

### Backend (`web-nodejs/`)
- **`GET /api/peers/:id`** — rozszerzona odpowiedź o pola:
  - `hardware` — CPU, GPU, RAM, dyski (z agent inventory lub sysinfo)
  - `software` — lista zainstalowanych aplikacji (z agent)
  - `services` — uruchomione usługi systemowe (z agent `system_services`)
  - `processes` — aktywne procesy (z agent `system_processes`)
  - `events` — logi systemowe (Windows Event Log / journalctl) (z agent `system_events`)
  - `usage_stats` — czas uruchomienia aplikacji (z agent `activity_tracker`)
- **`POST /api/peers/:id/rename`** — zmiana przyjaznej nazwy urządzenia (uprawnienie `device.edit`), audit-logowane.
- **`POST /api/peers/:id/files/browse`** — proxy do agenta: listowanie katalogów, nawigacja do rodzica, zezwolenie tylko na ścieżki w dozwolonym zakresie (path traversal guard).
- **`POST /api/peers/:id/files/read`** — pobranie zawartości pliku (max 1 MB), base64 w odpowiedzi.
- **`POST /api/peers/:id/terminal/execute`** — jednokrotne wykonanie polecenia przez agenta (bez PTY), audit-logowane z pełnym poleceniem i wyjściem.
- Uprawnienia: `device.view` do odczytu, `device.edit` do rename/terminal/files. Brak uprawnienia → 403.
- Agenci offline → odpowiedź `503 agent_offline`; timeout agenta → `504 agent_timeout`.

### Frontend (`web-nodejs/public/`)
- **`device-modal.js`** — nowy komponent pełnoekranowego modalu (zastępuje slide-over `device-detail`):
  - Otwierany z listy urządzeń na dashboardzie / urządzeniach.
  - Zakładki (wzorowane na nVision):
    - **General** — hero: nazwa, hostname, status, IP, system + szybkie akcje (Remote, Chat, Terminal, Files, Reboot, Shutdown).
    - **Activity** — wykres użycia aplikacji (czas pracy) z agent `activity_tracker`.
    - **Screenshots** — galeria screenshotów on-demand (z agent `screenshot_capture`).
    - **Events** — lista logów systemowych z filtrem po 심각ności (severity colors).
    - **DataGuard** — polityki DLP per-urządzenie (istniejący moduł).
    - **Blockades** — bany / ograniczenia urządzenia (istniejący moduł).
    - **Settings** — konfiguracja per-urządzenie (access policy, unattended mode, hasło).
  - Przycisk "Remote access" → otwiera `/remote/:id` (web viewer, już istnieje).
  - Przycisk "Files" → panel plików: nawigacja, upload/download, przycisk powrotu do katalogu nadrzędnego.
  - Przycisk "Terminal" → xterm.js w nowym oknie / zakładce modalu.
  - Retry button dla każdej zakładki agent-dependent.
- **`device-detail.css`** — stylowanie modalu (tables, event list, activity bars, file browser, loading spinner, error states).
- i18n: klucze `device_detail.*` (EN/PL/ZH) — 15 nowych kluczy na język.

### Agent — nowe capabilities (Rust, `betterdesk-agent-client/src-tauri/src/caps/`)
- `system_services.rs` — `Get-Service` (Win) / `systemctl list-units --type=service --all --no-pager --output=json` (Linux).
- `system_processes.rs` — `Get-Process` (Win) / `ps aux` (Linux), sortowanie po CPU/RAM.
- `system_events.rs` — `Get-EventLog` / `wevtutil` (Win) / `journalctl --output=json --no-pager -n 200` (Linux).
- `file_browser.rs` — `std::fs::read_dir` z `canonicalize`-based sandbox (blokada traversal poza dozwolonym rootem), read/write/delete.
- `screenshot_capture.rs` — `scrap` (Win) / `xcap` (Linux) + `image` crate, snapshot JPEG/PNG na żądanie, base64 w odpowiedzi.
- `activity_tracker.rs` — wątek w tle śledzący aktywne okno/proces i czas użycia, zapis do lokalnej bazy (SQLite w agent), eksport na żądanie.
- `terminal_session.rs` — jednorazowe `std::process::Command` (bez PTY w tej fazie), przechwytywanie stdout/stderr, limit czasu 30 s.

### Implementacja agenta
- Większość capabilities portowana z natywnego `betterdesk-agent` (Go) do Rust, lub uruchamiane jako sidecar subprocess przez Tawny.
- Komunikacja agent ↔ panel przez nowy WS `/ws/agent/{device_id}` (JWT z rejestracji).
- Każdy capability rejestruje handler na typ żądania `{type, request_id, payload}` i odpowiada `{type: 'command_response', request_id, ok, data?, error?}`.

### Definicja gotowości (DoD)
- [ ] Modal otwiera się dla dowolnego online urządzenia i pokazuje General z danymi z agenta.
- [ ] Wszystkie 6 zakładki renderują dane z agenta lub pokazują stan "agent offline".
- [ ] Rename plikuje do bazy i odświeża listę urządzeń.
- [ ] File browser pozwala nawigować w dół i do góry, czyta plik ≤1 MB.
- [ ] Terminal wykonuje polecenie i zwraca wyjście; akcja audit-logowana.
- [ ] Brak regression w istniejącym slide-over dla urządzeń offline (fallback).

### Szacunek czasu
2–3 sesje.

---

## Faza 3: Chat z brandingiem + E2E (FAZA 3)

**Cel:** Pełny czat między użytkownikami panelu a agentami, E2E, uploady plików, lista kontaktów.

### Backend (`web-nodejs/`)
- **WS `/ws/chat/agent/:device_id`** — WebSocket z JWT (token z rejestracji agenta lub sesji operatora). Reużywa `chatRelay.js` do routingu wiadomości między panel a agentem.
- **`GET /api/chat/contacts`** — lista kontaktów: operatorzy na górze (z `first_name`, `last_name`, `role_display`), poi pracownicy z organizacji, poi online agenci (device_id + hostname).
- **`POST /api/chat/attachment`** — upload pliku (max 50 MB), zapis encrypted blob, zwraca attachment ID.
- **`GET /api/chat/attachment/:id`** — pobranie attachment (decrypt po stronie klienta, E2E).
- **`GET /api/config/branding`** — logo, primary color, nazwa firmy (używane przez agenta do brandingu okna czatu).
- E2E: istniejące `chatCrypto.js` (P-256 ECDH + AES-256-GCM) — klucze wymieniane przy nawiązywaniu rozmowy, wiadomości szyfrowane end-to-end.

### Agent (`betterdesk-agent-client/src-tauri/src/`)
- **`chat.rs`** — WS client (tokio-tungstenite) do `/ws/chat/agent/:device_id`, reconnect, P-256 keypair (ring crate), encrypt/decrypt wiadomości.
- UI agenta: lewa kolumna kontakty (operatorzy na górze, ikona), prawa kolumna historia wiadomości.
- Upload: drag-and-drop + wklejenie obrazka (wklejka → automatyczny upload).
- Branding: pobiera `GET /api/config/branding` przy starcie czatu (logo, kolor, nazwa firmy).
- Powiadomienia o nowej wiadomości gdy okno czatu zamknięte (tray badge).

### Web panel (`web-nodejs/`)
- Strona `chat.ejs` rozszerzona o:
  - Lista agentów online (device_id + hostname, status zielony/czerwony).
  - Wybór odbiorcy: operator, kolega z firmy, klient (urządzenie).
  - Upload plików w czacie (przycisk przycinacza, lista przesyłanych z paskiem postępu).
  - E2E szyfrowanie już zaimplementowane (faza 2 — chatCrypto.js), wystarczy podłączyć do nowych endpointów.

### Protokół komunikacji
- Wiadomość czatu: `{type: 'chat_message', request_id, to_device_id, from, payload_encrypted, timestamp, attachment_id?}`.
- Odpowiedź: `{type: 'chat_ack', request_id, ok, error?}`.
- Typowanie (typing indicator): `{type: 'typing', device_id, is_typing}`.

### Bezpieczeństwo
- Wszystkie WS z JWT; brak JWT → odrzucenie połączenia WS.
- Attachmenty: max 50 MB, skanowanie nazwy pliku (path traversal), encrypted blob na dysku.
- Audit log: każda wiadomość, upload, pobranie attachmentu.

### Definicja gotowości (DoD)
- [ ] Operator może otworzyć czat z wybranym agentem online z panelu.
- [ ] Agent otrzymuje wiadomość w swoim oknie czatu (lub tray notification).
- [ ] Wiadomości są E2E szyfrowane (panel i agent mogą odszyfrować, serwer nie).
- [ ] Upload i download attachmentu ≤50 MB działa w obie strony.
- [ ] Lista kontaktów pokazuje operatorów, pracowników i online agentów.

### Szacunek czasu
1–2 sesje.

---

## Faza 4: Remote Desktop Core (FAZA 4 — NAJWIĘKSZA)

**Cel:** Pełny zdalny pulpit: multi-monitor, audio, wielokierunkowy schowek, transfer plików, tryby supervised i unattended.

### Agent — nowe crates (`src-tauri/Cargo.toml`)
- `scrap` / `xcap` — screen capture (Windows / Linux).
- `openh264` — video encode (fallback: JPEG klatki).
- `cpal` — audio capture (mikrofon systemu).
- `enigo` — input inject (already in MGMT): mysz, klawiatura.
- `arboard` — clipboard sync (bidirectional).
- `tokio-tungstenite` — WS do relay/signal.
- `prost` / `protobuf` — protokół (reuse z `betterdesk-server/proto`).

### Agent — nowe moduły (`src-tauri/src/remote/`)
- **`capture.rs`** — capture loop 30–60 FPS adaptive, multi-monitor, wykrywanie zmian (dirty regions) dla redukcji przepustowości.
- **`encoder.rs`** — H.264 encoder (openh264) + fallback VP9/JPEG, dynamiczna jakość w zależności od przepustowości.
- **`audio.rs`** — audio capture (cpal) + Opus encode, opcjonalny strumień dźwięku do operatora.
- **`input.rs`** — input injection receiver: ruch myszy, kliknięcia, klawisze (enigo), stosowanie uprawnień z consent mapy.
- **`session.rs`** — session manager: negocjacja codeca, jakości, multi-monitor, zarządzanie cyklem życia sesji zdalnej.
- **`consent.rs`** — popup supervised mode (wzór jak na zdjęciu 1):
  - Przyciski uprawnień: Klawiatura, Schowek, Audio, Transfer plików, Nagrywanie, Kamera, Blokada ekranu.
  - Dane operatora: avatar, imię+nazwisko, rola, organizacja (z `users` + branding).
  - Countdown "Automatyczna zgoda za X s" (opcjonalny, konfigurowalny).
  - Przyciski: Akceptuj / Odrzuć.
- **Unattended mode:** przełącznik w `/settings` agenta, akceptacja domyślna bez popupu, oparta na `access_policy` z bazy.

### Web viewer (`web-nodejs/views/remote.ejs`)
- Istniejący web remote client rozszerzony o:
  - Dropdown wyboru monitora (multi-monitor).
  - Przycisk "Request audio" → agent popup z prośbą o audio.
  - Przycisk "Start recording" → agent zapisuje MP4 (encoder), dostępne do pobrania po sesji.
  - Wskaźnik trybu: ikona tarczy (supervised) vs zakładka (unattended).
  - Kontrolka jakości (Speed/Balanced/Quality/Best).
  - Przyciski sterowania: pełny ekran, rozdzielczość, wyślij Ctrl+Alt+Del.

### Protokół zdalnej sesji
1. Agent rejestruje push connection: `WS /ws/agent/{device_id}`.
2. Operator łączy się przez web remote → serwer broadcastuje `connection_request` do agenta (z device_id operatora, uprawnieniami, czasem).
3. Agent:
   - Supervised → pokazuje popup consent → czeka na `accept` z mapą uprawnień → odpowiada `ready`.
   - Unattended → akceptuje od razu na podstawie access policy.
4. Obie strony łączą się do relay: `/relay/:session_id` (TCP/WS), serwer forwarduje bajty (istniejący `relay/` w Go server).
5. Strumienie: video (encoder), audio (opcjonalnie), input (od operatora do agenta), clipboard, file transfer.

### User identity (baza)
- Tabela `users`: nowe kolumny `first_name`, `last_name`, `email`, `phone`, `role_display` (np. "IT Support Level 2"), `avatar_url`.
- Popup consent w agencie pokazuje: avatar + imię+nazwisko + rola + organizacja.
- Endpoint `GET /api/users/me/profile` + `PUT /api/users/me/profile` (faza 4-5, déjà teilweise zrobione w PHASE_2_5_STATUS).

### Bezpieczeństwo
- Wszystkie strumienie sesji przez relay z JWT uwierzytelnieniem obu stron.
- Consent mapy egzekwowane po stronie agenta (input zablokowany bez zgody na klawiaturę/mysz).
- Nagrywanie tylko przy zgode użytkownika (przycisk w consent popup).
- Audit log: start/koniec sesji, użyte uprawnienia, transfer plików, zmiana schowka.

### Definicja gotowości (DoD)
- [ ] Operator może nawiązać sesję zdalną z panelu (web remote) z wybranym agentem.
- [ ] Agent w trybie supervised pokazuje popup consent i blokuje input bez zgody.
- [ ] Agent w trybie unattended akceptuje sesję bez popupu.
- [ ] Przekaz ekranu (multi-monitor), input myszy/klawiatury, audio działają przez relay.
- [ ] Wskaźnik trybu (supervised/unattended) widoczny w web viewer.
- [ ] Nagrywanie sesji i pobranie MP4 działa.
- [ ] Audit log rejestruje każdą sesję zdalną.

### Szacunek czasu
4–6 sesji.

---

## Faza 5: Agent Generator + Portal pobierania (FAZA 5)

**Cel:** Zaawansowany generator konfiguracji agenta w konsoli web + publiczny portal pobierania installerów z wbudowanym presetem.

### Generator (w panelu web, `generator.ejs`)
6-krokowy kreator:
1. **Template** — blank / organization preset / custom.
2. **Connection** — server, relay, TLS on/off, STUN/TURN.
3. **Access policy** — supervised / unattended / hybrid.
4. **Branding** — logo, kolor primary, nazwa firmy.
5. **Features** — chat, file transfer, terminal, screenshoty (włącz/wyłącz per capability).
6. **Security** — API key, lista dozwolonych operatorów, MAC pinning.
- **Generate button** → tworzy podpisany JSON config + enrollment token.
- Zapis do bazy: tabela `agent_templates` (`id`, `name`, `description`, `config_json`, `enrollment_token`, `created_by`, `org_id`, `created_at`, `updated_at`).
- Output: installer `.exe` / `.msi` / `.deb` / `.pkg` / `.dmg` z zaszytym configiem (build przez `cargo tauri build` ze zmienną `AGENT_PRESET_CONFIG`).
- Pobranie wygenerowanego installer lub enrollement token + jeden polecenie instalacyjne (one-liner).

### Portal pobierania (publiczny, port np. 5001 lub route prefix w konsoli)
- Nowa aplikacja / sekcja `downloads-portal` — dostęp publiczny (bez auth).
- Strona brandingowa: logo, nazwa firmy, opis, przyciski "Pobierz BetterDesk Agent" per OS (Windows, Linux, macOS).
- Każdy link pobiera najnowszy build z zaszytym preset configiem (z enrollment tokenem).
- Po instalacji agent auto-rejestruje się do serwera (token z config).

### Auto-enrollment flow (agent)
1. Agent startuje.
2. Jeśli `preset_enrollment_token` w config → `POST /api/bd/enroll` z tokenem + device_id + sysinfo.
3. Serwer weryfikuje token, tworzy device w bazie, zwraca JWT.
4. Agent zapisuje `device_id` + JWT → przechodzi w normalny flow rejestracji i WS.
5. Jeśli brak tokena → agent prosi o ręczne wprowadzenie server + token (fallback).

### Backend endpointy (`web-nodejs/routes/phase4_5.routes.js`, już częściowo)
- `GET /api/agent-templates` — list (uprawnienie `enrollment.manage`).
- `POST /api/agent-templates` — create, zwraca `enrollment_token`.
- `DELETE /api/agent-templates/:id` — usuń template.
- `POST /api/bd/enroll` — publiczny endpoint enrollement agenta.
- `GET /portal` — strona pobierania (branded download page, `views/downloads-portal.ejs`, już istnieje).
- `GET /api/portal/installers` — metadata installerów JSON.

### Tabela bazy
- `agent_templates` — auto-created przy pierwszym dostępie (idempotentna migracja): `id, name, description, config_json, enrollment_token, created_by, created_at, updated_at`.

### Bezpieczeństwo
- Enrollment token: jednorazowy lub ograniczona liczba użyć, wygaśnięcie (TTL).
- Podpisany JSON config (HMAC) — agent weryfikuje podpis przed użyciem.
- MAC pinning opcjonalny: agent akceptuje tylko na wskazanych MAC addressach.
- Rate-limit na `/api/bd/enroll` (przeciw brute-force tokenów).

### Definicja gotowości (DoD)
- [ ] Kreator 6 kroków generuje podpisany JSON config + enrollment token.
- [ ] Template zapisany w bazie i widoczny na liście `agent-templates`.
- [ ] Instalator z wbudowanym configiem buduje się i po instalacji agent auto-rejestruje się.
- [ ] Portal pobierania udostępnia installer per OS bez logowania.
- [ ] Enrollment endpoint weryfikuje token i zwraca JWT.
- [ ] Wygaśnięcie i limit użyć enrollment tokenów egzekwowane.

### Szacunek czasu
1–2 sesje.

---

## Kolejność realizacji

| Faza | Zakres | Czas (szacunek) | Priorytet | Zależności |
|------|--------|----------------|-----------|------------|
| 1. Fundament UX + powiadomienia | Tray, dzwonek, notifications API | Zrobione | 🔴 Krytyczne | — |
| 2. Device Management Modal | device-modal.js, 6 zakładek, agent capabilities (services/processes/events/files/terminal/screenshot/activity) | 2–3 sesje | 🟠 Wysokie | Faza 1 (WS agent) |
| 3. Chat E2E + attachments | WS chat, kontakty, attachmenty, branding | 1–2 sesje | 🟠 Wysokie | Faza 1 (JWT, chatCrypto) |
| 4. Remote Desktop Core | capture/encoder/audio/input/session/consent, web viewer, relay sesje | 4–6 sesji | 🔴 Krytyczne | Faza 2 (agent capabilities), Faza 3 (WS) |
| 5. Generator + Portal | generator.ejs 6 kroków, agent_templates, downloads-portal, auto-enrollment | 1–2 sesje | 🟡 Średnie | Faza 4 (consent, unattended) |

**Łączny szacunek:** ok. 9–14 sesji implementacyjnych (bez Fazy 1).

## Uwagi bezpieczeństwa (cross-cutting)

- **JWT token z rejestracji** — używany do wszystkich WS (agent side) + device API.
- **Rate-limit IP** — na wszystkich publicznych endpointach (istnieje w Go server).
- **Audit log** — każda akcja (login, connect, file transfer, command exec, remote session) do `audit_log` tabeli.
- **E2E chat** — już zaimplementowane (P-256 ECDH + AES-256-GCM) w `chatCrypto.js`.
- **Token rotation** — JWT krótki TTL (15 min) + refresh token.
- **Certificate pinning** — agent pinuje SHA256 serwera po pierwszej rejestracji.
- **Supervised mode consent** — user ma fizyczną kontrolę nad uprawnieniami per-sesja.
- **Admin-only actions w agencie** — ustawienia, unregister, zamknięcie — wymagają OS admin (lokalny).
- **Path traversal guard** — wszystkie operacje plikowe agenta walidowane przez `canonicalize` + dozwolony root.
- **Consent mapy egzekwowane po stronie agenta** — serwer nie może obejść braku zgody użytkownika.

## Kolejność realizacji

| Faza | Czas (szacunek) | Priorytet |
|------|----------------|-----------|
| 1. Fundament UX + powiadomienia | Ta sesja | 🔴 Krytyczne |
| 2. Device Modal + agent capabilities | 2-3 sesje | 🟠 Wysokie |
| 3. Chat E2E + attachments | 1-2 sesje | 🟠 Wysokie |
| 4. Remote Desktop | 4-6 sesji | 🔴 Krytyczne |
| 5. Generator + Portal | 1-2 sesje | 🟡 Średnie |

## Uwagi bezpieczeństwa (cross-cutting)

- **JWT token z rejestracji** — używany do wszystkich WS (agent side) + device API.
- **Rate-limit IP** — na wszystkich publicznych endpointach (istnieje w Go server).
- **Audit log** — każda akcja (login, connect, file transfer, command exec) do `audit_log` tabeli.
- **E2E chat** — już zaimplementowane (P-256 ECDH + AES-256-GCM) w `chatCrypto.js`.
- **Token rotation** — JWT krótki TTL (15 min) + refresh token.
- **Certificate pinning** — agent pinuje SHA256 serwera po pierwszej rejestracji.
- **Supervised mode consent** — user ma fizyczną kontrolę nad uprawnieniami per-sesja.
- **Admin-only actions w agencie** — ustawienia, unregister, zamknięcie — wymagają OS admin (lokalny).
