# 📊 COMPARAISON — Méthodes d'installation des Runtimes

> Panda IDE supporte 3 méthodes pour installer Node.js et autres runtimes.

---

## 🔍 Vue d'ensemble

| Méthode | Commande | Taille | Vitesse | Fiabilité | Maintenance |
|---|---|---|---|---|---|
| **Alpine (apk)** | `apk add nodejs` | ~30MB | ⚡ Rapide | ✅ Haute | ✅ Auto |
| **PFD (Play Feature)** | Settings → Runtimes | ~80MB | 🐌 Lente | ✅ Haute | ⚠️ Manuel |
| **HTTP Direct** | `curl` + `chmod` | ~25MB | ⚡ Rapide | ⚠️ Moyenne | ⚠️ Manuel |

---

## 📦 Méthode 1 : Alpine Linux (apk)

### Comment ça marche
```
Terminal → proot → Alpine rootfs → apk add nodejs
```

### Avantages
| Avantage | Détail |
|---|---|
| ✅ **Package manager** | `apk add nodejs npm` — gère les dépendances |
| ✅ **Mises à jour** | `apk upgrade` — met à jour tous les paquets |
| ✅ **Multi-runtime** | Node, Python, Ruby, Go, Rust, etc. dans le même rootfs |
| ✅ **Minimal** | Alpine est léger (~5MB base) |
| ✅ **Shell complet** | bash, sh, coreutils, git, curl disponibles |
| ✅ **Isolement** | PRoot sépare le filesystem Android du rootfs |

### Inconvénients
| Inconvénient | Détail |
|---|---|
| ⚠️ **Dépend de PRoot** | Nécessite `libproot.so` + `libproot-loader.so` |
| ⚠️ **Performance** | PRoot ajoute ~10-20% de surcoût (syscall interception) |
| ⚠️ **Taille totale** | Alpine rootfs + paquets = ~100-200MB |
| ⚠️ **Première instal** | Télécharge le rootfs (~5MB) + `apk update` (~2MB) |

### Commandes
```bash
# Installer Alpine (première fois)
# → Settings → Runtimes → Alpine Linux

# Installer Node.js
apk update
apk add nodejs npm

# Vérifier
node --version
npm --version

# Installer d'autres runtimes
apk add python3
apk add ruby
apk add go
apk add rust
```

### Score : ⭐⭐⭐⭐ (4/5)

---

## 📦 Méthode 2 : Play Feature Delivery (PFD)

### Comment ça marche
```
Settings → Runtimes → Node.js → Download via Play Store → Extract to binDir
```

### Avantages
| Avantage | Détail |
|---|---|
| ✅ **Pas de rootfs** | Binaire natif Android, pas besoin de PRoot |
| ✅ **Performance** | Aucun surcoût — exécution native |
| ✅ **Fiabilité** | Binaires testés par l'équipe Panda |
| ✅ **Resume** | Téléchargement reprend là où il s'est arrêté |

### Inconvénients
| Inconvénient | Détail |
|---|---|
| ❌ **Taille** | ~80MB par runtime (compressé) |
| ❌ **Lent** | Téléchargement via Play Store peut être lent |
| ❌ **Pas de npm** | Seul le binaire `node` est inclus, pas `npm` |
| ❌ **Pas de mises à jour** | Doit être réinstallé manuellement |
| ❌ **Un runtime à la fois** | Chaque runtime = un download séparé |
| ❌ **Play Store requis** | Ne fonctionne que si l'app est installée via Play Store |

### Runtimes disponibles
| Runtime | Module | Archive | Taille |
|---|---|---|---|
| Node.js | `node_feature` | `node.zip` | ~80MB |
| Python | `python_feature` | `python.zip` | ~80MB |
| Dart | `dart_feature` | `dart.zip` | ~80MB |
| Clang | `clang_feature` | `clang.zip` | ~80MB |
| Rust | `rust_feature` | `rust.zip` | ~80MB |
| Go | `go_feature` | `go.zip` | ~80MB |
| Ruby | `ruby_feature` | `ruby.zip` | ~80MB |
| Lua | `lua_feature` | `lua.zip` | ~80MB |
| Java | `java_feature` | `java-21-openjdk.zip` | ~80MB |
| Kotlin | `kotlin_feature` | `kotlin.zip` | ~80MB |

### Score : ⭐⭐⭐ (3/5)

---

## 📦 Méthode 3 : Téléchargement HTTP Direct

### Comment ça marche
```
curl -o node https://nodejs.org/dist/v20.x/node-v20.x-android-arm64
chmod +x node
```

### Avantages
| Avantage | Détail |
|---|---|
| ✅ **Léger** | ~25MB seulement (binaire seul) |
| ✅ **Rapide** | Téléchargement direct, pas de Play Store |
| ✅ **Flexible** | N'importe quelle version de Node.js |
| ✅ **Pas de dépendance** | Fonctionne sans Alpine ni PFD |

### Inconvénients
| Inconvénient | Détail |
|---|---|
| ⚠️ **Pas de npm** | Seul le binaire node, pas le gestionnaire de paquets |
| ⚠️ **Pas de mises à jour** | Doit être réinstallé manuellement |
| ⚠️ **Dépend de curl** | Nécessite curl ou un client HTTP |
| ⚠️ **Binaires non testés** | Peut ne pas fonctionner sur certains appareils |

### Score : ⭐⭐ (2/5)

---

## 📊 Comparaison détaillée

| Critère | Alpine (apk) | PFD (Play) | HTTP Direct |
|---|---|---|---|
| **Node.js** | ✅ `apk add nodejs` | ✅ Binaire | ✅ Binaire |
| **npm** | ✅ `apk add npm` | ❌ Non inclus | ❌ Non inclus |
| **Python** | ✅ `apk add python3` | ✅ Binaire | ⚠️ Difficile |
| **Ruby** | ✅ `apk add ruby` | ✅ Binaire | ❌ Non |
| **Go** | ✅ `apk add go` | ✅ Binaire | ✅ Binaire |
| **Rust** | ✅ `apk add rust` | ✅ Binaire | ✅ Binaire |
| **Git** | ✅ `apk add git` | ❌ Non | ❌ Non |
| **curl** | ✅ `apk add curl` | ❌ Non | ⚠️ Nécessaire |
| **Mises à jour auto** | ✅ `apk upgrade` | ❌ Non | ❌ Non |
| **Dépendances** | ✅ Auto-résolues | ❌ Non | ❌ Non |
| **Taille totale** | ~100-200MB | ~80MB/runtime | ~25MB |
| **Performance** | ⚠️ -10-20% (PRoot) | ✅ Native | ✅ Native |
| **Isolement** | ✅ PRoot | ❌ Partagé | ❌ Partagé |
| **Complexité** | 🟡 Moyenne | 🟢 Facile | 🟢 Facile |

---

## 🏆 Recommandation

### Pour les extensions VS Code (Live Server, ESLint, etc.)
**→ Alpine (apk)** est le meilleur choix car :
- `npm install` gère les dépendances des extensions
- `apk add` installe les outils nécessaires
- Le surcoût PRoot est négligeable pour des extensions

### Pour les runtimes de compilation (Node, Python, Dart)
**→ PFD** est recommandé car :
- Binaire natif = performance maximale
- Pas besoin de npm pour exécuter du code
- Téléchargement géré par le Play Store

### Pour les tests rapides
**→ HTTP Direct** est suffisant pour :
- Tester un binaire node rapidement
- Pas besoin de npm ou de dépendances

---

## 🔧 Implémentation dans Panda IDE

### Alpine (recommandé pour extensions)
```
Terminal → proot → Alpine rootfs → apk add nodejs npm
```
- Alpine rootfs : `runtimes/alpine-linux/`
- PRoot : `lib/libproot.so`, `lib/libproot-loader.so`
- Session : `proot -0 -w /root/workspace -r alpine-linux /bin/sh`

### PFD (recommandé pour runtimes)
```
Settings → Runtimes → [Runtime] → Download → Extract
```
- Binaires : `binDir/node`, `binDir/python3`, etc.
- Module : `node_feature`, `python_feature`, etc.
- Archive : `node.zip`, `python.zip`, etc.

### HTTP Direct (pour tests)
```
curl -L -o binDir/node <url>
chmod +x binDir/node
```

---

*Comparaison générée le 24 août 2026 — Panda IDE 0.x*
