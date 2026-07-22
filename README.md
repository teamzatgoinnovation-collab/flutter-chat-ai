# Chat AI — Flutter client

Mobile chat client for the Frappe **`chat_ai`** app. Tabs: **Chat** and **Settings**.

**Backend:** `chat_ai.api.chat.*`  
**SDK:** [`SharedSDK/dart_sdk`](../../../SharedSDK/dart_sdk/)  
**Role:** Chat AI User (or Chat AI Manager / System Manager)

## Run

```bash
cd Clients/flutter/chat_ai
flutter pub get
flutter run --dart-define=FRAPPE_BASE_URL=https://erp.zatgo.online
```

Default site URL is `https://demo.zatgo.online` if `FRAPPE_BASE_URL` is omitted. Sign in with ERPNext email/password.

## Features

- Session list, new chat, history, send
- Tool / plan confirmation resume
- Rename, clear, archive, delete session
- Settings: language, assistant mode, site ping, sign out

LLM provider keys stay in Desk → **Chat AI Settings** (managers only).

## Key methods

| Action | Method |
|--------|--------|
| Send | `chat_ai.api.chat.send` |
| Sessions | `new_session`, `list_sessions`, `history` |
| Prefs | `set_language`, `set_mode`, `get_ui_locale` |
| Session ops | `rename`, `archive`, `delete_session`, `clear` |
