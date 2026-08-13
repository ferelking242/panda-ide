# 🗺️ Roadmap : Évolution de Panda Linux (Alternative Moderne à Termux)

L'objectif de cette roadmap est de transformer l'environnement actuel (Alpine Linux via PRoot) en un terminal hybride surpassant Termux. Nous allons utiliser des technologies modernes pour combler les lacunes de l'architecture "chroot simulé" et offrir une expérience native, rapide et interconnectée.

## 🚀 Phase 1 : Optimisation des Performances (CPU & I/O)
*Problème actuel : PRoot intercepte tous les appels système (syscalls) via `ptrace`, ce qui ralentit les opérations lourdes (compilation, npm install).*
* **1.1. Intégration de SECCOMP-BPF** : Utiliser les filtres seccomp modernes pour réduire le nombre d'interceptions `ptrace`. Termux utilise cette technique via `proot-distro` pour réduire l'overhead de manière significative.
* **1.2. Compilation Statique Hybride** : Au lieu de tout faire tourner sous PRoot, exécuter les outils les plus lourds (ex: `node`, `git`, `rustc`) en mode natif (compilés avec Bionic pour Android) tout en partageant le même système de fichiers (`/data/data/...`) que l'environnement Alpine.
* **1.3. VFS Caching** : Implémenter un cache en mémoire pour le Virtual File System (VFS) afin d'accélérer la lecture des milliers de petits fichiers générés par les frameworks modernes.

## 🌉 Phase 2 : Panda-API (Le Pont Android ↔ Linux)
*Problème actuel : Les scripts Alpine sont isolés et ne peuvent pas interagir avec le téléphone (Notifications, Batterie, Presse-papier).*
* **2.1. Démon de communication (Panda Socket)** : Lancement d'un serveur de sockets UNIX ou d'un serveur HTTP local géré par l'application Flutter en arrière-plan.
* **2.2. CLI `/usr/bin/panda`** : Création d'un exécutable injecté dans Alpine permettant de faire des requêtes au démon Flutter.
  - *Exemples de commandes* : 
    - `panda clipboard get` / `set`
    - `panda notify --title "Build fini"`
    - `panda share file.apk`
    - `panda camera take photo.jpg`
* **2.3. Gestionnaire de Permissions** : L'app Flutter demandera dynamiquement l'autorisation à l'utilisateur si un script Linux tente d'accéder au micro ou à la caméra.

## ⚙️ Phase 3 : Gestionnaire de Services (Le remplaçant de Systemd)
*Problème actuel : Impossible de lancer des daemons proprement (PostgreSQL, Redis) car Android bloque le démarrage via PID 1.*
* **3.1. Implémentation d'un Superviseur Léger** : Intégrer `runit` ou `s6` (comme le fait `termux-services`), ou créer notre propre `panda-services` écrit en Go/Rust.
* **3.2. CLI Service** : 
  - `panda-service enable postgresql`
  - `panda-service start redis`
* **3.3. Cycle de vie Android** : Lier les services Linux au cycle de vie de l'application Flutter (Android WorkManager) pour empêcher le système de tuer les bases de données quand l'app passe en arrière-plan.

## 🌐 Phase 4 : Résolution des Restrictions Réseau
*Problème actuel : Android bloque les requêtes ICMP (`ping`) et empêche d'ouvrir des ports inférieurs à 1024.*
* **4.1. Patch DNS & Ping** : Remplacer l'outil `ping` classique par une version qui utilise des sockets datagram non privilégiés (méthode de contournement Termux). Configurer le `/etc/resolv.conf` pour s'interfacer avec le DNS dynamique du réseau WiFi actuel de l'appareil (via l'API Flutter).
* **4.2. Port Forwarding Local** : Si l'utilisateur veut utiliser le port 80 pour un serveur web, créer un proxy local dans Flutter qui écoute sur le port 80 (si possible, sinon le 8080) et redirige vers le port interne de l'environnement Alpine.

## 🖥️ Phase 5 : Support Graphique (Serveur X11 / Wayland embarqué)
*Problème actuel : Aucune possibilité de lancer des interfaces graphiques Linux.*
* **5.1. Serveur d'affichage interne** : Intégrer un serveur X11 (comme `Termux-X11`) ou un composteur Wayland directement dans une vue (Widget) Flutter.
* **5.2. Connecteur Alpine** : Configurer la variable d'environnement `DISPLAY` dans Alpine pour pointer vers le socket local de notre serveur d'affichage.
* **5.3. Cas d'usage** : Lancer des IDE lourds (Linux VSCode), des éditeurs d'images (GIMP) ou un bureau XFCE complet, directement dans un onglet "Panda Desktop".

## 🛠️ Ordre de Priorité Suggéré (Pour le développement)
1. **Panda-API (Phase 2)** : C'est ce qui apportera le plus de valeur immédiate (interactivité avec Android).
2. **Gestionnaire de Services (Phase 3)** : Essentiel pour le web-development (DBs, serveurs).
3. **Optimisation SECCOMP (Phase 1)** : Pour rendre l'utilisation fluide au quotidien.
4. **Support Réseau (Phase 4)** : Pour un environnement réseau robuste.
5. **Support Graphique (Phase 5)** : Le "Endgame", un atout marketing énorme.
