# Security

## Private vault: what it protects

The vault encrypts hidden videos and their metadata on the device.

| Protection | How |
| --- | --- |
| Video encryption | AES-256-GCM in 1 MiB authenticated chunks (hardware AES via the platform crypto APIs). Each chunk is bound to its file, position and the file length, so tampering, reordering and truncation are detected |
| Metadata encryption | The vault's video list (names, original locations, sizes) is sealed with AES-256-GCM |
| Playback | Encrypted videos stream to the player through a loopback-only HTTP server that decrypts on the fly. Plaintext is never written to storage. Each stream URL carries a random 256-bit token and is revoked when playback ends or the vault locks |
| Key hierarchy | Each vault has a random 256-bit data key. It is stored only in wrapped form: under the password, under the recovery answers (main vault), and the decoy key also under the main key. Wrapping keys come from PBKDF2-HMAC-SHA256 (120,000 iterations, random salt). The unwrapped key stays in memory only while the vault is unlocked |
| Password storage | PBKDF2-HMAC-SHA256, 120,000 iterations, 16-byte random salt per hash, constant-time comparison. Derivation runs off the UI isolate |
| Guessing | After 5 failed unlock or recovery attempts, a lockout starts at 30 s and doubles with each further failure (capped at 1 h) |
| Decoy vault | A second password opens a separate vault with its own key. The decoy can't read the main vault, change the main password or set recovery questions |
| Recovery | Recovery questions can only be set from the unlocked main vault. Answers are hashed and compared ignoring case and whitespace. Recovery unwraps the data key with the answers and re-wraps it under the new password, so encrypted videos stay readable. The decoy password is unchanged |
| Backups | Android cloud backup and device-to-device transfer are disabled |
| Logs | `debugPrint` is disabled in release builds |

### Upgrading from older versions

Earlier versions moved videos into the vault **without encryption** and
stored unsalted SHA-256 password hashes. On the first unlock after
upgrading:

1. The password hash is replaced with a PBKDF2 hash and a data key is
   created.
2. The owner of the main vault is asked to enter their recovery questions
   again, so the new data key can be recovered with them.
3. Opening the vault encrypts the existing videos in the background. Each
   file is encrypted to a new file first, and the plain copy is deleted only
   after the metadata points at the encrypted one, so an interruption never
   loses a video.

### Not in scope

- Share and unhide produce a decrypted copy, by definition. Share copies go
  to the app's temp folder and are wiped on the next launch.
- Flash storage can keep remnants of deleted plain files from before the
  upgrade; encryption protects what is stored from now on.
- Anyone who knows the password (or the recovery answers) can decrypt the
  vault. The lockout counter lives in app storage, and clearing app data also
  deletes the vault.
- A decoy vault first opened after upgrading has a key the main vault can't
  unwrap. Until the vault is re-created, the owner can't rotate the decoy
  password (`changePassword` refuses rather than orphan its files).

## Network

Cleartext HTTP is permitted because users can open arbitrary `http://`
streams. Release builds trust only system certificate authorities; user-added
CAs are trusted in debug builds only
([network_security_config.xml](android/app/src/main/res/xml/network_security_config.xml)).

## Reporting a vulnerability

Please report security issues privately to the repository owner rather than
opening a public issue.
