# Security

## Private vault: what it protects

The vault hides videos from other apps and from casual access to the device.

| Protection | How |
| --- | --- |
| Files hidden from gallery and file managers | Videos are moved into app-private storage under random names with a `.vault` extension, next to a `.nomedia` marker |
| Password storage | PBKDF2-HMAC-SHA256, 120,000 iterations, 16-byte random salt per hash, constant-time comparison. Derivation runs off the UI isolate |
| Guessing | After 5 failed unlock or recovery attempts, a lockout starts at 30 s and doubles per further failure (capped at 1 h) |
| Decoy vault | A second password opens a separate, independent vault. The decoy cannot change the main password or configure recovery questions |
| Recovery | Recovery questions can only be set from the unlocked main vault. Answers are hashed like passwords and compared case- and whitespace-insensitively. Recovery sets a new main password chosen by the user; the decoy password is unchanged |
| Backups | Android cloud backup and device-to-device transfer are disabled, so hashes and vault files never leave the device |
| Logs | `debugPrint` is disabled in release builds |

### Not in scope

- **Files are not encrypted.** Anyone with root access, a forensic image of
  the device, or a debuggable build can read vault files directly. The
  streaming AES code path in `VaultService` is retained only to open videos
  hidden by older versions that enabled it.
- The lockout counter lives in app storage; clearing app data resets it (and
  also deletes the vault).
- Recovery answers are only as strong as the answers chosen.

### Upgrading from older versions

Earlier versions stored unsalted SHA-256 password hashes. These still unlock
the vault and are transparently replaced with PBKDF2 hashes on the next
successful unlock. Recovery answers are upgraded the next time they are set.

## Network

Cleartext HTTP is permitted because users can open arbitrary `http://`
streams. Release builds trust only system certificate authorities; user-added
CAs are trusted in debug builds only
([network_security_config.xml](android/app/src/main/res/xml/network_security_config.xml)).

## Reporting a vulnerability

Please report security issues privately to the repository owner rather than
opening a public issue.
