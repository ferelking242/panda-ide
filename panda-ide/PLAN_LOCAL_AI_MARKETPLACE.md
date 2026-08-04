# 🐼 Panda IDE — Plan : Local AI Model Marketplace

> **Objectif** : Intégrer un système complet de gestion de modèles IA locaux dans Panda IDE,
> rivalisant avec Cursor/Replit, mais fonctionnant entièrement hors-ligne sur Android.
> Ce plan couvre l'architecture, le marketplace, la détection matérielle, les sources de modèles
> et les optimisations d'inférence.

---

## Table des matières

1. [Vue d'ensemble de l'architecture](#1-vue-densemble-de-larchitecture)
2. [Marketplace des modèles locaux](#2-marketplace-des-modèles-locaux)
   - 2.1 [Tuiles et piles de modèles](#21-tuiles-et-piles-de-modèles)
   - 2.2 [Page de détail d'un modèle](#22-page-de-détail-dun-modèle)
   - 2.3 [Système de téléchargement](#23-système-de-téléchargement)
3. [Détection matérielle du téléphone](#3-détection-matérielle-du-téléphone)
   - 3.1 [Ce qu'on détecte](#31-ce-quon-détecte)
   - 3.2 [Analyse et recommandation automatique](#32-analyse-et-recommandation-automatique)
4. [Sources des modèles](#4-sources-des-modèles)
   - 4.1 [Dépôt principal : Hugging Face](#41-dépôt-principal--hugging-face)
   - 4.2 [Créateurs fiables GGUF](#42-créateurs-fiables-gguf)
   - 4.3 [Catalogue JSON centralisé](#43-catalogue-json-centralisé)
5. [Moteurs d'inférence](#5-moteurs-dinférence)
6. [Gestion du stockage](#6-gestion-du-stockage)
7. [Optimisations d'inférence](#7-optimisations-dinférence)
8. [Catégories du catalogue](#8-catégories-du-catalogue)
9. [Modèle de données : fiche d'un modèle](#9-modèle-de-données--fiche-dun-modèle)
10. [Intégration dans l'IDE](#10-intégration-dans-lide)
11. [Phases de développement](#11-phases-de-développement)

---

## 1. Vue d'ensemble de l'architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Panda IDE                            │
│                                                             │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │  Marketplace │   │  Détection   │   │  Moteur        │  │
│  │  Local AI    │◄──│  Matérielle  │──►│  d'inférence   │  │
│  │  (nouvelle   │   │  (Hardware   │   │  (llama.cpp    │  │
│  │   section)   │   │   Profiler)  │   │   + fallbacks) │  │
│  └──────┬───────┘   └──────────────┘   └────────────────┘  │
│         │                                        ▲          │
│         ▼                                        │          │
│  ┌──────────────┐   ┌──────────────┐            │          │
│  │  Catalogue   │   │  Download    │            │          │
│  │  JSON +      │──►│  Manager     │────────────┘          │
│  │  HF API      │   │  (intelligent│                       │
│  └──────────────┘   │   resumable) │                       │
│                      └──────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

**Principe clé** : tout fonctionne localement, sans cloud, sans abonnement.
Le réseau n'est utilisé que pour télécharger les modèles depuis Hugging Face.

---

## 2. Marketplace des modèles locaux

### 2.1 Tuiles et piles de modèles

Le marketplace est organisé en **piles verticales** (colonnes scrollables), chacune
représentant une famille ou un thème de modèles.

```
┌─────────────────────────────────────────────────────────────┐
│  🏪 Local Models Marketplace                    [🔍] [⚙️]  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ⭐ Recommandés pour votre appareil                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐      │
│  │ Qwen2.5  │ │  Phi-4   │ │ Gemma 3  │ │ Llama 3.2│      │
│  │ Coder    │ │  Mini    │ │ 4B-IT    │ │ 3B       │      │
│  │ 1.5B Q4  │ │ 3.8B Q4  │ │  Q4_K_M  │ │  Q4_K_M  │      │
│  │ 💾 0.9GB │ │ 💾 2.1GB │ │ 💾 2.4GB │ │ 💾 1.8GB │      │
│  │ ⚡ Fast  │ │ ⚡ Good  │ │ ⚡ Good  │ │ ⚡ Fast  │      │
│  │[Téléch.] │ │[Téléch.] │ │[Téléch.] │ │[Téléch.] │      │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘      │
│                                                             │
│  💻 Coding                                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                    │
│  │DeepSeek  │ │Qwen2.5   │ │ StarCoder│                    │
│  │ Coder    │ │ Coder 7B │ │   2 3B   │                    │
│  │ 1.3B Q4  │ │  Q4_K_M  │ │  Q4_K_M  │                    │
│  │ ...      │ │ ...      │ │ ...      │                    │
│  └──────────┘ └──────────┘ └──────────┘                    │
│                                                             │
│  🌍 Général  │  🧠 Reasoning  │  👁️ Vision  │  🛠️ Tools  │
│  ...         │  ...           │  ...        │  ...        │
└─────────────────────────────────────────────────────────────┘
```

**Comportement des tuiles :**
- Tap → ouvre la page de détail
- Long press → options rapides (télécharger, partager, supprimer)
- Badge vert si déjà installé
- Badge bleu si une mise à jour est disponible
- Barre de progression pendant le téléchargement (inline dans la tuile)

**Piles disponibles :**

| Pile | Icône | Description |
|------|-------|-------------|
| Recommandés | ⭐ | Filtrés selon la RAM et le CPU détectés |
| Coding | 💻 | Complétion, explication, génération de code |
| Général | 🌍 | Chat, résumé, traduction |
| Reasoning | 🧠 | Raisonnement multi-étapes, math, logique |
| Vision | 👁️ | Analyse d'images, screenshots de code |
| Tool Calling | 🛠️ | Appel de fonctions, agents autonomes |
| Léger (<2GB) | 📱 | Pour appareils avec peu de RAM |
| Nouveau | 🆕 | Dernières sorties sur Hugging Face |

---

### 2.2 Page de détail d'un modèle

Chaque modèle dispose d'une **page de détail complète** accessible depuis sa tuile.

```
┌─────────────────────────────────────────────────────────────┐
│  ← Retour          Qwen2.5-Coder-7B-Instruct-Q4_K_M        │
│                                                 ⭐ Favori   │
├─────────────────────────────────────────────────────────────┤
│  [Logo/icône du modèle]                                     │
│  Qwen2.5 Coder 7B                                           │
│  by Qwen (Alibaba Cloud)                    ⭐⭐⭐⭐⭐ Code  │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 💾 Taille       │ 4.68 GB                             │ │
│  │ 📐 Format       │ GGUF Q4_K_M                         │ │
│  │ 🧠 Contexte     │ 128K tokens                         │ │
│  │ 💬 Tool Calling │ ✅ Oui                              │ │
│  │ 👁️ Vision       │ ❌ Non                              │ │
│  │ 🔢 Reasoning    │ ✅ Oui                              │ │
│  │ 🏃 RAM minimale │ 8 GB                                │ │
│  │ ⚡ Vitesse est. │ ~15 tok/s (sur votre appareil)     │ │
│  │ 🌐 Source       │ bartowski / HuggingFace             │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│  Compatibilité avec votre appareil                         │
│  ████████████░░░░  78%  ✅ Compatible                      │
│                                                             │
│  Description                                               │
│  Qwen2.5 Coder est spécialisé dans la génération et        │
│  l'explication de code. Supporte 92 langages de            │
│  programmation. Excellent pour la complétion inline,       │
│  la revue de code et la génération de tests unitaires.     │
│                                                             │
│  Capacités                                                  │
│  [Code] [Python] [JS] [Rust] [Go] [Tool Use] [128K ctx]   │
│                                                             │
│  Quantizations disponibles                                 │
│  ○ Q2_K   1.7GB  (très léger, qualité réduite)            │
│  ○ Q4_K_S 2.2GB  (bon compromis)                          │
│  ● Q4_K_M 4.7GB  ← Recommandé pour votre appareil        │
│  ○ Q5_K_M 5.4GB                                           │
│  ○ Q8_0   7.1GB  (proche du FP16, RAM requise élevée)     │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  💾 Espace libre : 12.4 GB   SD Card : 45.2 GB    │   │
│  │  📦 Destination : ○ Interne  ● SD Card            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  [    ⬇️  Télécharger Q4_K_M (4.68 GB)    ]               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Contenu de la page de détail :**
- Header : nom, auteur, note coding (étoiles)
- Tableau de specs techniques
- Jauge de compatibilité calculée en temps réel selon le matériel
- Description en langage naturel
- Tags de capacités cliquables (filtre dans le marketplace)
- Sélecteur de quantization avec explication simple de chaque niveau
- Sélecteur de destination (stockage interne / SD card)
- Bouton de téléchargement principal (quantization recommandée pré-sélectionnée)
- Section "Modèles similaires" en bas de page

---

### 2.3 Système de téléchargement

Le Download Manager est le cœur du système. Il doit être robuste car les modèles
font plusieurs gigaoctets.

**Fonctionnalités obligatoires :**

#### Téléchargement intelligent
- **Reprise après interruption** : utilisation des headers HTTP `Range` pour continuer
  un téléchargement interrompu (réseau coupé, app en background, batterie faible)
- **Téléchargement par morceaux** (chunked) : découper le fichier en blocs de 64 MB,
  permettant la reprise à n'importe quel bloc
- **Vérification SHA256** : après chaque chunk et en fin de téléchargement, vérifier
  l'intégrité contre le hash fourni par Hugging Face
- **File de priorité** : plusieurs modèles peuvent être mis en file, avec pause/reprise
  individuelle et glisser-déposer pour réordonner

#### Progression détaillée
```
Téléchargement : Qwen2.5-Coder-7B-Q4_K_M
████████████████░░░░░░░░░░  62%  (2.9 / 4.68 GB)
⬇️ 8.4 MB/s   ⏱️ 4 min restantes   📶 WiFi
[Pause]   [Annuler]   [Changer vers SD]
```

#### Notifications
- Notification Android persistante pendant le téléchargement
- Notification de succès avec action "Charger le modèle" au clic
- Notification d'erreur avec bouton "Reprendre"

---

## 3. Détection matérielle du téléphone

### 3.1 Ce qu'on détecte

Au premier lancement (et à chaque mise à jour de l'app), Panda IDE lance un
**Hardware Profiler** qui collecte :

```dart
class DeviceProfile {
  // CPU
  String cpuModel;          // ex: "Snapdragon 8 Gen 3"
  String cpuArch;           // ARM64, x86_64
  List<String> cpuFeatures; // NEON, SVE, SVE2, SME, dotprod, i8mm...
  int cpuCores;             // total
  int cpuPerformanceCores;  // Big cores (ex: 4)
  int cpuEfficiencyCores;   // Small cores (ex: 4)
  int cpuFrequencyMHz;      // fréquence max

  // RAM
  int totalRamMB;
  int availableRamMB;

  // GPU
  String gpuModel;          // ex: "Adreno 750"
  String gpuVendor;         // Qualcomm, ARM Mali, PowerVR, Apple...
  bool gpuOpenCLSupport;
  bool gpuVulkanSupport;
  int gpuMemoryMB;          // si détectable

  // NPU / DSP
  bool npuDetected;
  String npuName;           // ex: "Hexagon 798"

  // Stockage
  int internalStorageFreeGB;
  int sdCardFreeGB;         // 0 si pas de SD
  bool sdCardWritable;

  // Thermique
  bool thermalThrottlingDetected;

  // Score global calculé (0-100)
  int performanceScore;
}
```

**Sources de données :**
- `android.os.Build` → modèle, fabricant, version Android
- `/proc/cpuinfo` → features ARM, cœurs
- `ActivityManager.getMemoryInfo()` → RAM totale et disponible
- `EGL/Vulkan` → info GPU
- `StatFs` → espace disque
- `CpuInfo` via `Process` → fréquence des cœurs

### 3.2 Analyse et recommandation automatique

Après la collecte, un algorithme de scoring détermine les modèles adaptés :

```
Score de performance = f(RAM, CPU cores, GPU, NPU)
```

**Tableau de recommandation par RAM :**

| RAM totale | Recommandation principale | Quantization |
|------------|--------------------------|--------------|
| < 4 GB | 0.5B – 1B | Q4_K_S |
| 4 – 6 GB | 1.5B | Q4_K_M |
| 6 – 8 GB | 3B | Q4_K_M |
| 8 – 12 GB | 7B | Q4_K_M |
| 12 – 16 GB | 8B | Q4_K_M |
| > 16 GB | 13B+ | Q5_K_M ou Q8_0 |

**Résultat affiché à l'utilisateur :**

```
┌──────────────────────────────────────────────────────┐
│  📱 Analyse de votre appareil terminée               │
│                                                      │
│  Snapdragon 8 Gen 3 · 12 GB RAM · Adreno 750        │
│  Score de performance : 84/100 ⚡ Excellent          │
│                                                      │
│  ✅ Modèles jusqu'à 7B Q4_K_M recommandés           │
│  ✅ GPU offload disponible (Adreno 750 + Vulkan)     │
│  ✅ ARM SVE2 détecté → performances optimales        │
│  ⚠️  SD Card non détectée                           │
│                                                      │
│  [ Voir les modèles recommandés ]                    │
└──────────────────────────────────────────────────────┘
```

---

## 4. Sources des modèles

### 4.1 Dépôt principal : Hugging Face

**URL de base de l'API :** `https://huggingface.co/api/`

Panda IDE utilise l'API publique de Hugging Face pour :
- Lister les modèles par tag (`gguf`, `text-generation`, etc.)
- Récupérer les métadonnées (taille, auteur, tags, scores)
- Obtenir les liens de téléchargement directs (CDN HF)
- Surveiller les nouvelles sorties (endpoint `/models?sort=lastModified`)

**Format GGUF uniquement** pour llama.cpp. Filtrage via le tag `gguf` sur l'API HF.

### 4.2 Créateurs fiables GGUF

Ces créateurs sont reconnus pour la qualité et la fiabilité de leurs conversions GGUF.
Ils constituent le catalogue curé de Panda IDE :

| Créateur | HF Handle | Spécialité |
|---------|-----------|------------|
| bartowski | `bartowski` | Conversions GGUF de référence, tous modèles |
| unsloth | `unsloth` | GGUF optimisés, fine-tunes rapides |
| Qwen (Alibaba) | `Qwen` | Modèles Qwen officiels, excellent coding |
| Google | `google` | Gemma, Gemma 2, PaliGemma |
| Meta | `meta-llama` | Llama 3, Llama 3.1, Llama 3.2 |
| Microsoft | `microsoft` | Phi-3, Phi-4 |
| Mistral AI | `mistralai` | Mistral, Mixtral |
| DeepSeek | `deepseek-ai` | DeepSeek Coder, DeepSeek R1 |
| 01-ai | `01-ai` | Yi series |

**Politique du catalogue :**
- Seuls des modèles de ces créateurs (ou des forks vérifiés) apparaissent dans le marketplace
- Un fichier `catalog.json` hébergé par Panda maintient la liste validée
- L'utilisateur peut ajouter manuellement un lien HF direct (mode "avancé")

### 4.3 Catalogue JSON centralisé

Panda IDE maintient un fichier `catalog.json` versionné qui est téléchargé au lancement
pour mettre à jour le marketplace. Structure :

```json
{
  "version": "2026.08.01",
  "models": [
    {
      "id": "qwen2.5-coder-7b-instruct",
      "name": "Qwen2.5 Coder 7B Instruct",
      "author": "Qwen",
      "hf_repo": "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF",
      "description": "...",
      "categories": ["coding", "tool_calling"],
      "capabilities": {
        "tool_calling": true,
        "vision": false,
        "reasoning": true,
        "context_length": 131072,
        "coding_score": 5,
        "min_ram_gb": 8
      },
      "quantizations": [
        {
          "level": "Q4_K_M",
          "size_gb": 4.68,
          "hf_filename": "qwen2.5-coder-7b-instruct-q4_k_m.gguf",
          "sha256": "...",
          "recommended_for_ram_gb": 8
        }
      ],
      "speed_estimate": {
        "snapdragon_8_gen3_toks": 15,
        "snapdragon_888_toks": 6
      }
    }
  ]
}
```

---

## 5. Moteurs d'inférence

### Moteur principal : llama.cpp

**Pourquoi llama.cpp ?**
- Runtime universel, le plus testé sur Android
- Support natif GGUF
- Accélération via NEON (ARM), Vulkan (GPU), OpenCL
- Communauté massive, mises à jour fréquentes
- Base de : Ollama, LM Studio, Jan, PocketPal

**Binding Android existant dans le projet :** `llama_flutter_android`

### Architecture extensible (future)

```
┌────────────────────────────────────────────────────┐
│              InferenceEngineManager                │
│                                                    │
│  ┌────────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ llama.cpp  │  │ MLC-LLM  │  │ ONNX Runtime  │  │
│  │  (défaut)  │  │ (option) │  │   (futur)     │  │
│  │   GGUF     │  │ NPU/GPU  │  │               │  │
│  └────────────┘  └──────────┘  └───────────────┘  │
│                                                    │
│  Sélection automatique selon DeviceProfile         │
└────────────────────────────────────────────────────┘
```

**Règles de sélection automatique :**
- Appareil avec NPU Hexagon puissant + MLC-LLM installé → MLC-LLM proposé
- Sinon → llama.cpp (toujours disponible, fallback garanti)

---

## 6. Gestion du stockage

### Détection de l'espace disponible
- Vérification avant chaque téléchargement
- Alerte si l'espace est insuffisant avec suggestion de libérer ou de basculer sur SD
- Affichage en temps réel dans la page de détail

### Destinations de stockage

```
/storage/emulated/0/Android/data/com.panda.ide/models/   ← interne
/storage/XXXX-XXXX/Android/data/com.panda.ide/models/    ← SD card
```

### Cache LRU (Least Recently Used)
- Chaque modèle enregistre sa date de dernier chargement
- Option dans les settings : "Supprimer auto les modèles non utilisés depuis X jours"
- Alerte si stockage < 2 GB avec liste des modèles supprimables

### Index local des modèles installés

```json
{
  "installed": [
    {
      "id": "qwen2.5-coder-7b-instruct-q4km",
      "path": "/storage/.../models/qwen2.5-coder-7b-q4_k_m.gguf",
      "size_gb": 4.68,
      "installed_at": "2026-08-01T10:23:00Z",
      "last_used_at": "2026-08-04T08:15:00Z",
      "storage": "internal"
    }
  ]
}
```

---

## 7. Optimisations d'inférence

Ces optimisations sont configurées automatiquement selon le `DeviceProfile` :

| Optimisation | Description | Condition d'activation |
|-------------|-------------|----------------------|
| **Prompt Cache** | Réutilise les embeddings du system prompt | Toujours activé |
| **KV Cache** | Cache key-value pour l'historique de conversation | Toujours activé |
| **Flash Attention** | Attention efficace en mémoire | Si llama.cpp le supporte + GPU détecté |
| **Speculative Decoding** | Utilise un petit modèle draft pour accélérer | Si 2 modèles chargés |
| **Batch Decoding** | Traite plusieurs tokens en parallèle | Activé auto |
| **GPU Offload** | Décharge des couches sur GPU | Si Vulkan/OpenCL disponible |
| **Streaming** | Token par token en temps réel | Toujours activé |
| **mmap GGUF** | Chargement mémoire mappé (pas de copie) | Toujours activé |
| **Annulation instantanée** | Stop la génération immédiatement | Toujours activé |

**Paramètres configurables (mode avancé) :**
```
n_gpu_layers : 0 - max    (0 = CPU only, max = tout sur GPU)
n_threads    : 1 - N      (auto = performance cores)
n_ctx        : 512 - 128K (contexte actif)
n_batch      : 128 - 2048 (batch size de prompt)
```

---

## 8. Catégories du catalogue

### Structure des piles dans le marketplace

Chaque pile a une icône, un titre, une description courte et un filtre sur les capacités :

```
⭐ Recommandés   → triés par compatibilité (score DeviceProfile)
💻 Coding        → coding_score >= 4
🌍 Général       → général, chat, multilingual
🧠 Reasoning     → reasoning: true
👁️ Vision        → vision: true
🛠️ Tool Calling  → tool_calling: true
📱 Légers <2GB   → size_gb < 2
🆕 Nouveautés    → sortis dans les 30 derniers jours
```

---

## 9. Modèle de données : fiche d'un modèle

Chaque modèle exposé dans le marketplace déclare ses capacités via une fiche
standardisée. C'est ce qui permet à l'IDE de choisir automatiquement le bon modèle :

```
Nom           : Qwen2.5-Coder-7B-Instruct
Auteur        : Qwen (Alibaba Cloud)
Taille        : 4.68 GB (Q4_K_M)
Format        : GGUF
Tool Calling  : ✅
Vision        : ❌
Reasoning     : ✅
Contexte      : 128K tokens
Coding ⭐⭐⭐⭐⭐ : 5/5
RAM minimale  : 8 GB
Vitesse est.  : ~15 tok/s (Snapdragon 8 Gen 3)
Source        : bartowski @ HuggingFace
```

### Sélection automatique par tâche

L'IDE utilise ces fiches pour choisir le bon modèle selon la tâche en cours :

| Tâche | Modèle sélectionné |
|-------|--------------------|
| Complétion de code inline | Modèle coding_score max dans la RAM dispo |
| Chat développeur | Modèle général + tool_calling |
| Analyse d'un screenshot | Modèle vision |
| Agent autonome (appels d'outils) | Modèle tool_calling + reasoning |
| Explication mathématique | Modèle reasoning |

---

## 10. Intégration dans l'IDE

### Où s'intègre le marketplace

- **Activity Bar** : nouvelle icône 🧠 "Local Models" (entre Extensions et Source Control)
- **Settings** : section "Local AI" avec gestion des modèles actifs
- **Status Bar** : indicateur du modèle actif (ex: `🐼 Qwen2.5-Coder 7B`)
- **AI Panel** : bouton "Changer de modèle" (ouvre le marketplace filtré)

### Flux utilisateur type

```
1. L'utilisateur ouvre "Local Models" dans l'activity bar
2. Le marketplace s'affiche avec les piles
3. La pile "Recommandés" est en premier, filtrée selon son téléphone
4. Il clique sur "Qwen2.5 Coder 7B"
5. La page de détail s'ouvre avec la quantization recommandée pré-sélectionnée
6. Il choisit la destination (interne / SD)
7. Il clique "Télécharger"
8. Le téléchargement démarre en arrière-plan (notification Android)
9. Quand c'est fini, notif "Qwen2.5 Coder prêt — Charger maintenant"
10. Il charge le modèle → la status bar se met à jour → l'AI panel est prêt
```

---

## 11. Phases de développement

### Phase 1 — Fondations (Sprint 1-2)
- [ ] `DeviceProfiler` : collecte CPU/RAM/GPU/stockage
- [ ] `CatalogService` : téléchargement et parsing de `catalog.json` depuis HF
- [ ] `ModelDownloadManager` : téléchargement chunked + reprise + SHA256
- [ ] UI Marketplace de base : piles + tuiles (sans page de détail)

### Phase 2 — Détail et recommandations (Sprint 3-4)
- [ ] Page de détail des modèles
- [ ] Sélecteur de quantization
- [ ] Algorithme de recommandation basé sur DeviceProfile
- [ ] Sélecteur de stockage (interne / SD card)

### Phase 3 — Optimisations llama.cpp (Sprint 5-6)
- [ ] Configuration automatique n_gpu_layers selon Vulkan/OpenCL
- [ ] Activation Flash Attention si disponible
- [ ] Streaming token par token dans le chat panel
- [ ] Annulation instantanée de la génération

### Phase 4 — Intelligence et polish (Sprint 7-8)
- [ ] Cache LRU + nettoyage automatique
- [ ] Sélection automatique du modèle selon la tâche IDE
- [ ] Mode avancé (paramètres llama.cpp manuels)
- [ ] Notifications rich Android (progress, success, erreur)
- [ ] Extension du catalogue (50+ modèles)

---

*Plan rédigé le 2026-08-04 — Panda IDE Local AI Marketplace*
*Version 1.0 — Ne pas coder avant validation de ce plan*
