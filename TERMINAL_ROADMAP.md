# 🗺️ Roadmap : Panda Linux (Alternative Hybride à Termux)

Cette roadmap détaille l'évolution de Panda Linux. Contrairement à une simple implémentation PRoot, Panda Linux utilise une **Architecture Hybride** mêlant l'isolation de PRoot (Alpine) avec l'exécution native Android (Bionic) pour des performances optimales, orchestrée par un pont de communication Android (Panda Bridge).

## 🏆 Architecture Cible

```text
PANDA LINUX
                              │
              ┌───────────────┴───────────────┐
              │                               │
        Android / Flutter                Linux Userspace
              │                               │
       Panda Native Runtime              Alpine + PRoot
              │                               │
       ┌──────┼──────┐                 ┌──────┼──────┐
       │      │      │                 │      │      │
      Git   Node   Python             bash   apk   gcc
       │      │      │                 │      │      │
       └──────┴──────┘                 └──────┴──────┘
              │                               │
              └────────── Panda Bridge ───────┘
                              │
                    Android APIs / Services
```

---

## 🚦 Les Phases de Développement

### 🔴 Phase 0 : Panda Runtime (La fondation)
Création des abstractions de base dans l'application Flutter sans faire un runtime monolithique massif.
*   **Process Manager** : Gestion du cycle de vie des processus.
*   **Filesystem Manager** : Gestion des chemins et abstraction `/data/data/...`.

### 🔴 Phase 1 : Panda-API / Android Bridge (Interactivité)
*Le plus gros avantage compétitif immédiat.*
*   **Socket de communication** : Un serveur TCP/Unix local géré par Flutter.
*   **CLI `/bin/panda` dans Alpine** : Un script qui relaie les commandes vers l'API Flutter.
*   **Commandes cibles** :
    *   `panda clipboard get` / `set`
    *   `panda notify "Message"`
    *   `panda share file.apk`
    *   `panda intent open https://...`

### 🔴 Phase 2 : Native FastPath (Outils Limités)
*Contourner PRoot pour les outils critiques en I/O via des builds Android/Bionic.*
*   **Pas de détection magique** : Utilisation explicite au départ via des "shims" ou un préfixe.
*   **Outils cibles** : `git`, `node`, `python`, `clang`.
*   *Exemple* : L'appel à `/usr/bin/node` dans Alpine est redirigé (shim) vers le binaire Android natif géré par Panda.

### 🔴 Phase 3 : Services & Foreground Supervisor
*Gestion des daemons Linux sans utiliser Android WorkManager pour des processus continus.*
*   **Supervisor Linux** : Intégration de `s6` ou `runit` dans l'environnement Alpine pour gérer les services (ex: `postgres`, `redis`, `nginx`).
*   **Android Foreground Service** : Un service Android persistant qui maintient le superviseur Linux en vie lorsque l'application est en arrière-plan.

### 🟠 Phase 4 : Réseau (DNS & Proxy de Ports)
*Contourner intelligemment les limites du noyau Android.*
*   **DNS Mapping** : Synchroniser automatiquement le DNS du réseau Android avec `/etc/resolv.conf`.
*   **Panda Port Proxy** : Android non-rooté ne peut pas lier de port < 1024. Mise en place d'une commande `panda server expose 8080` pour relier proprement un port interne (Alpine) à un port externe (Android), et potentiellement fournir un proxy local de l'espace LAN (192.168.x.x:8080 -> Alpine:8080).

### 🟡 Phase 5 : FastPath Générique (R&D)
*Le challenge technique majeur.*
*   **Gestion dynamique du linking (Bionic ↔ musl)** : Créer un orchestrateur capable de détecter à la volée si une commande doit tourner sous PRoot ou en natif, et gérer proprement les variables d'environnement (`LD_LIBRARY_PATH`) pour éviter les conflits de bibliothèques C.

### 🟢 Phase 6 : Wayland / Desktop (Endgame)
*Interface graphique Linux embarquée dans Flutter.*
*   **Compositeur Wayland** intégré dans un Widget Flutter.
*   Permettre l'exécution de VS Code Linux, XFCE, ou d'autres applications GUI avec affichage direct et natif dans un onglet "Panda Desktop".

