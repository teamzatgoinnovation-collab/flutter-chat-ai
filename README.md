# Chat AI — Flutter client

Mobile chat client for **Chat AI** on DigitalOcean ERPNext (`https://erp.zatgo.online`).

Tabs: **Chat** and **Settings**.

**Backend:** `zatgo_core.api.v1.chat_ai.*` (proxies `chat_ai`)  
**SDK:** [`SharedSDK/dart_sdk`](../../../SharedSDK/dart_sdk/)  
**Role:** Chat AI User (or Chat AI Manager / System Manager)

## Run

```bash
cd Clients/flutter/chat_ai
flutter pub get
flutter run
```

Default site is `https://erp.zatgo.online` (override with `--dart-define=FRAPPE_BASE_URL=…` if needed). Sign in with username and password only.

## Features

- Session list, new chat, history, send
- Tool / plan confirmation resume
- Rename, clear, archive, delete session
- Settings: language, assistant mode, probe, sign out

LLM provider keys stay in Desk → **Chat AI Settings** (managers only).

## Key methods

| Action | Method |
|--------|--------|
| Send | `zatgo_core.api.v1.chat_ai.chat.send` |
| Sessions | `new_session`, `list_sessions`, `history` |
| Prefs | `set_language`, `set_mode`, `get_ui_locale` |
| Session ops | `rename`, `archive`, `delete_session`, `clear` |
