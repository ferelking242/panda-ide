# 📱 Panda Device

Extension `.panda` officielle de Panda IDE — **développe sur ton propre téléphone, comme si c'était un PC.**

Façon Shizuku : l'extension t'accompagne pas à pas pour transformer ton appareil Android en machine de développement complète.

## Le flux

```
┌─────────────────────────────────────────────────────────┐
│  1. Ouvre les Options développeur (intent Android)      │
│  2. Guide le Débogage sans fil + notification d'aide    │
│     pendant la saisie du code (comme Shizuku)           │
│  3. adb pair + connect automatiques                     │
│     (loopback → fallback IP WiFi, comme sur Samsung)    │
│  4. Vérifie Flutter → installe si absent                │
│     avec barre de progression dans son UI               │
│  5. ▶ Run : flutter run sur l'appareil                  │
│     (hot reload r / hot restart R)                      │
└─────────────────────────────────────────────────────────┘
```

## Installation

Depuis le marketplace Panda IDE, ou en ligne de commande :

```bash
panda_ext install panda-device-1.0.0.panda
```

## Développement

```bash
panda_ext dev .
panda_ext package .
```

## Architecture

| Fichier | Rôle |
|---------|------|
| `panda.yaml` | Manifest (commands, sidebar view, config, permissions) |
| `lib/extension.dart` | Orchestration du wizard (PandaExtension) |
| `lib/adb_service.dart` | Appairage WiFi adb, détection appareil, intents |
| `lib/flutter_setup.dart` | Install SDK avec progression (tarball+greffe git, fallback dart-sdk.zip) |
| `lib/views/device_panel.dart` | Vue sidebar (étapes + progression + Run) |

## Notes techniques

- **Deux ports différents** : le port d'*appairage* (popup du code) ≠ port de *débogage* (écran principal). L'extension gère les deux.
- **Samsung refuse le loopback** : `127.0.0.1` échoue → fallback automatique sur l'IP WiFi du téléphone.
- **Réseau instable sous proot** : tous les téléchargements utilisent `curl -C - --retry` (reprise) et le tarball+greffe git au lieu du RPC git.
