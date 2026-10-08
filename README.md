# Callify

Callify is a Flutter app for pairing two anonymous users in a one-to-one,
audio-only call. Firestore provides the waiting queue and LiveKit provides the
real-time audio room.

## What happens when a user taps **Start Call**

1. `HomePage` opens `CallPage`.
2. `CallController` gets a persistent anonymous device ID from
   `SharedPreferences`.
3. The controller creates `waiting_queue/{deviceId}` in Firestore with
   `status: waiting`.
4. It looks for the oldest other waiting user and uses a Firestore transaction
   to claim both records. This ensures two users cannot claim the same partner.
5. Both queue records receive the same generated LiveKit room ID.
6. Each device observes its own queue record, then connects to that LiveKit
   room and publishes microphone audio.
7. On cancel, hang-up, or normal page exit, the queue record is deleted and
   the LiveKit room connection is disposed.

## Project structure

```text
lib/
├── main.dart                                      App startup and Firebase init
├── core/
│   ├── constants/app_constants.dart                Shared app values
│   ├── theme/app_theme.dart                        Material theme
│   └── utils/device_id_store.dart                  Anonymous device ID storage
└── features/
    ├── home/presentation/pages/home_page.dart     Landing page / Start Call button
    └── call/
        ├── data/datasources/matchmaking_data_source.dart  Firestore queue logic
        ├── data/services/livekit_service.dart            LiveKit audio connection
        ├── domain/entities/call_state.dart               Call lifecycle states
        └── presentation/
            ├── controllers/call_controller.dart          Call orchestration
            └── pages/call_page.dart                      Call UI
```

## Key files for handover

| File | Responsibility |
| --- | --- |
| `matchmaking_data_source.dart` | Creates, queries, atomically matches, observes, and removes queue records. |
| `call_controller.dart` | Owns the state machine, timers, queue subscription, and cleanup flow. |
| `livekit_service.dart` | Generates a LiveKit token, connects audio, receives participant events, and releases room resources. |
| `call_page.dart` | Renders search/match/connect/call/end states and invokes cleanup when leaving the page. |

## Call states

```text
idle → searching → matched → connecting → connected → ended
                      └──────────────────────────→ error
```

`searching` means the device has a queue record. `matched` is the short
partner-found screen before the LiveKit connection begins.

## Firestore data model

Collection: `waiting_queue`

```json
{
  "userId": "device_...",
  "status": "waiting | matched",
  "matchedWith": "device_... | null",
  "roomId": "livekit-room-id | null",
  "role": "caller | callee | null",
  "timestamp": "Firestore server timestamp",
  "lastSeen": "Firestore server timestamp"
}
```

The matcher selects a `waiting` record created within the last two minutes.
It re-reads that record in a transaction before updating both users to
`matched`.

## Important production gap: offline queue entries

An absent queue document cannot be matched. However, a user who force-closes
the app or loses network can leave behind a `waiting` document. The current
two-minute timestamp filter means that stale entry can still be selected during
that window, so an online user may be paired with someone unavailable.

Before production, add all of the following:

- A `lastSeen` heartbeat refreshed every 15–30 seconds while searching.
- Match only records with a recent `lastSeen` value.
- A server-side scheduled cleanup for expired queue documents.
- App lifecycle handling that removes the queue record when the app backgrounds
  or terminates where the OS permits it.
- A timeout while waiting for the partner to join the LiveKit room; return the
  remaining user to the queue or show a retry option.

Client cleanup alone is best-effort and is not sufficient for offline users.

## Local setup

Prerequisites: Flutter SDK compatible with Dart `^3.12.1`, a Firebase project,
and a LiveKit project/server.

```bash
flutter pub get
flutter run
```

Firebase is initialized with `Firebase.initializeApp()`. Ensure each target
platform has its Firebase configuration (for example,
`android/app/google-services.json` on Android; add iOS/Web configuration when
those platforms are enabled).

## Security and deployment checklist

- **Move LiveKit token creation to a trusted backend** such as Firebase Cloud
  Functions. The current client-side token generation contains a LiveKit API
  secret and must not be shipped in a production build.
- Rotate the existing LiveKit credentials after migrating them off the client.
- Write Firestore Security Rules so a client may create/update/delete only its
  own queue document. Do not allow unrestricted writes to `waiting_queue`.
- Matchmaking queries by `status` and filters the `lastSeen` heartbeat locally,
  so it does not require a manually deployed composite Firestore index.
- Confirm microphone permission is present and tested on Android and iOS.
- Use a unique authenticated user ID when authentication is introduced; the
  current identity is an anonymous ID persisted per installation.

## Testing

Run the current automated checks:

```bash
flutter analyze
flutter test
```

For manual multi-user testing, use two physical devices (or a device and
emulator) with separate app storage. Start a call on both devices, verify they
receive the same room ID and connect, then test cancel, hang-up, backgrounding,
network loss, and force-close while searching.

For concurrency testing at 100–200 users, do not rely only on client devices.
Use a controlled test harness against a Firebase Emulator or a dedicated test
project, and verify that every matched pair is unique, no user is matched twice,
and expired queue entries are never selected.

## Common changes

- Change matching rules or queue expiry: `matchmaking_data_source.dart`.
- Change the call lifecycle, retry behavior, or timeout: `call_controller.dart`.
- Change the audio provider or connection behavior: `livekit_service.dart`.
- Change call UI: `call_page.dart`.
