# Argos Unified Observability Platform — Plan complet

> **Objectif** : Transformer le fork `ferelking242/argos-observability` (basé sur OpenObserve) en une
> plateforme unifiée qui couvre logs, traces, métriques, crash reporting (Sentry-compatible) et
> analytics utilisateur — réutilisable sur tous tes projets (Panda IDE, apps futures).
>
> **Ce document est le brief pour un agent de code.** Toutes les décisions d'architecture sont ici.
> L'agent doit lire ce fichier au démarrage et suivre le plan section par section.

---

## 1. Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Argos Unified Platform                            │
│                                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │  Logs / Core │  │   Crashes    │  │   Analytics  │  │  Metrics   │  │
│  │ (OpenObserve)│  │   (Sentry-   │  │  (PostHog-   │  │   (OTEL)   │  │
│  │     base)    │  │  compatible) │  │  compatible) │  │            │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └─────┬──────┘  │
│         └─────────────────┴─────────────────┴────────────────┘         │
│                              Argos Ingest Layer                          │
│                     (Go proxy micro-service, port 9999)                  │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↑
             SDKs clients (Dart/Flutter, JS/TS, Python)
```

**Stratégie** : OpenObserve gère le stockage et le dashboard. On ajoute un **proxy Go léger**
(`argos-ingest`) qui expose des API compatibles Sentry et PostHog, traduit les payloads en
logs/events OpenObserve, et injecte les métadonnées d'enrichissement.

---

## 2. Stack cible

| Composant | Tech | Rôle |
|---|---|---|
| `argos-core` | OpenObserve (Rust, existant) | Stockage, dashboard, alertes, SQL queries |
| `argos-ingest` | Go 1.22 | Proxy API — expose Sentry/PostHog/OTEL endpoints |
| `argos-sdk-dart` | Dart/Flutter pub package | SDK client pour Panda IDE et apps Flutter |
| `argos-sdk-js` | TypeScript npm package | SDK client pour apps web/Node |
| Docker Compose | | Orchestration dev + prod |

---

## 3. Structure du repo

```
argos-observability/
├── core/                      # Fork OpenObserve (existant, ne pas toucher)
├── ingest/                    # NOUVEAU — Go proxy micro-service
│   ├── main.go
│   ├── handlers/
│   │   ├── sentry.go          # /api/{project}/envelope/ (Sentry DSN compat)
│   │   ├── posthog.go         # /capture/, /batch/ (PostHog compat)
│   │   ├── otel.go            # /v1/traces, /v1/metrics (OTEL compat)
│   │   └── health.go          # /health
│   ├── forwarder/
│   │   └── openobserve.go     # Traduit vers OpenObserve REST API
│   ├── enrichment/
│   │   └── enricher.go        # Ajoute app_id, env, release, user_id
│   ├── config/
│   │   └── config.go          # Env vars + YAML config
│   └── Dockerfile
├── sdks/
│   ├── dart/                  # NOUVEAU — package Dart
│   │   ├── lib/
│   │   │   ├── argos.dart     # Entry point
│   │   │   ├── logger.dart    # Structured logging
│   │   │   ├── crash.dart     # Crash reporter (FlutterError + PlatformDispatcher)
│   │   │   ├── analytics.dart # Event tracking
│   │   │   └── transport.dart # HTTP batch transport
│   │   └── pubspec.yaml
│   └── js/                    # NOUVEAU — package TypeScript
│       ├── src/
│       │   ├── index.ts
│       │   ├── logger.ts
│       │   ├── crash.ts
│       │   └── analytics.ts
│       └── package.json
├── docker-compose.yml          # MODIFIÉ — ajoute argos-ingest
├── docker-compose.prod.yml
└── docs/
    ├── integration-flutter.md
    └── integration-web.md
```

---

## 4. argos-ingest — spécifications Go

### 4.1 Configuration (env vars)

```
ARGOS_INGEST_PORT=9999
ARGOS_OPENOBSERVE_URL=http://openobserve:5080
ARGOS_OPENOBSERVE_ORG=default
ARGOS_OPENOBSERVE_AUTH=base64(user:pass)
ARGOS_SECRET_KEY=<token pour authentifier les SDKs>
```

### 4.2 Endpoints Sentry-compatible

```
POST /api/{project_id}/envelope/
```
- Parse le format Sentry envelope (header JSON + items JSON séparés par `\n`)
- Extrait : `exception`, `message`, `event_id`, `release`, `user`, `contexts`
- Traduit en log OpenObserve stream `crashes` avec niveau `error`
- Répond `{"id":"<event_id>"}` (Sentry attend ça)

```
POST /api/{project_id}/store/
```
- Alias Sentry legacy — même traitement

### 4.3 Endpoints PostHog-compatible

```
POST /capture/
POST /batch/
```
- Parse les events PostHog : `event`, `distinct_id`, `properties`, `timestamp`
- Traduit en log OpenObserve stream `analytics`
- Groupe les propriétés dans `properties` JSON field

### 4.4 Endpoints OTEL

```
POST /v1/traces   (protobuf ou JSON)
POST /v1/metrics  (protobuf ou JSON)
POST /v1/logs     (protobuf ou JSON)
```
- Transmet directement vers OpenObserve OTEL endpoint (`/api/{org}/traces`)

### 4.5 Endpoint natif Argos (logs structurés)

```
POST /argos/ingest
Content-Type: application/json

{
  "stream": "app_logs",
  "app_id": "panda-ide",
  "env": "production",
  "entries": [
    {
      "level": "error",
      "message": "Something failed",
      "timestamp": "2026-08-04T12:00:00Z",
      "data": { "key": "value" }
    }
  ]
}
```

---

## 5. argos-sdk-dart — spécifications Flutter

### 5.1 API publique

```dart
// Initialisation (dans main.dart, avant runApp)
await Argos.init(ArgosConfig(
  url: 'https://argos.yourserver.com',
  secretKey: 'your-secret-key',
  appId: 'panda-ide',
  release: '2.3.0',
  environment: 'production',   // ou 'development'
  enableCrashReporting: true,
  enableAnalytics: true,
  batchIntervalMs: 30000,      // flush toutes les 30s
  debug: false,                // true → logs dans console
));

// Logging
Argos.log('Agent started', level: ArgosLevel.info, data: {'model': 'gpt-4o'});
Argos.error('Tool failed', error: exception, stackTrace: st);

// Analytics
Argos.track('agent_message_sent', properties: {
  'mode': 'agent',
  'provider': 'openai',
  'model': 'gpt-4o',
  'token_estimate': 1200,
});

// Identifier un utilisateur
Argos.identify('user-uuid-123', traits: {
  'plan': 'free',
  'install_date': '2026-01-01',
});

// Flush manuel (ex: avant fermeture app)
await Argos.flush();
```

### 5.2 Crash reporting automatique

```dart
// Dans ArgosConfig(enableCrashReporting: true) :
// → Intercept FlutterError.onError
// → Intercept PlatformDispatcher.instance.onError
// → Intercept isolate uncaught errors
// → Envoie au endpoint Sentry-compatible /api/{appId}/envelope/
// → Aucune config sentry_flutter nécessaire
```

### 5.3 Transport batch

- Buffer en mémoire : max 500 entrées
- Flush auto toutes les `batchIntervalMs` ms
- Flush sur crash (synchrone via `Isolate.current.addErrorListener`)
- Retry 3x avec backoff exponentiel sur erreur réseau
- Désactivé si `environment == 'development'` et `debug == false`

### 5.4 Intégration dans PandaLog existant

```dart
// Dans panda_log.dart — ajouter RemoteTransport optionnel
class PandaLog {
  static ArgosTransport? _remote;

  static void initRemote(ArgosTransport transport) {
    _remote = transport;
  }

  static void _log(String level, String tag, String msg, ...) {
    // ... code existant ...
    _remote?.enqueue(level: level, tag: tag, message: msg, ...);
  }
}
```

---

## 6. argos-sdk-js — spécifications TypeScript

```typescript
import { Argos } from '@argos/sdk';

Argos.init({
  url: 'https://argos.yourserver.com',
  secretKey: 'your-secret-key',
  appId: 'my-web-app',
  release: '1.0.0',
  environment: 'production',
});

Argos.log('Page loaded', { page: '/dashboard' });
Argos.track('button_clicked', { button: 'upgrade' });
Argos.captureException(new Error('Something broke'));
```

- Taille bundle : < 8KB gzipped
- Compatible browser + Node.js
- Auto-capture `window.onerror` et `unhandledrejection`

---

## 7. docker-compose.yml — diff

```yaml
# Ajouter au docker-compose.yml existant :

  argos-ingest:
    build: ./ingest
    ports:
      - "9999:9999"
    environment:
      ARGOS_OPENOBSERVE_URL: http://openobserve:5080
      ARGOS_OPENOBSERVE_ORG: default
      ARGOS_OPENOBSERVE_AUTH: ${OPENOBSERVE_AUTH}
      ARGOS_SECRET_KEY: ${ARGOS_SECRET_KEY}
    depends_on:
      - openobserve
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9999/health"]
      interval: 30s
      timeout: 5s
      retries: 3
```

---

## 8. Ordre d'implémentation (pour l'agent de code)

### Phase 1 — argos-ingest (Go proxy) [PRIORITÉ HAUTE]
1. `ingest/config/config.go` — lire env vars
2. `ingest/forwarder/openobserve.go` — client HTTP vers OpenObserve
3. `ingest/handlers/sentry.go` — parse envelope Sentry → forward
4. `ingest/handlers/posthog.go` — parse events PostHog → forward
5. `ingest/handlers/otel.go` — proxy OTEL transparent
6. `ingest/handlers/health.go` — GET /health → 200 OK
7. `ingest/main.go` — gorilla/mux router, graceful shutdown
8. `ingest/Dockerfile` — multi-stage build Go
9. `docker-compose.yml` — ajouter service argos-ingest
10. Tests unitaires pour chaque handler (`_test.go`)

### Phase 2 — argos-sdk-dart [PRIORITÉ HAUTE]
1. `sdks/dart/pubspec.yaml` — deps (http, shared_preferences)
2. `sdks/dart/lib/transport.dart` — buffer + flush batch
3. `sdks/dart/lib/logger.dart` — structured logging
4. `sdks/dart/lib/crash.dart` — FlutterError + PlatformDispatcher hooks
5. `sdks/dart/lib/analytics.dart` — event tracking + identify
6. `sdks/dart/lib/argos.dart` — API publique + init
7. Tests widget + unit

### Phase 3 — argos-sdk-js [PRIORITÉ MOYENNE]
1. `sdks/js/package.json` — setup
2. `sdks/js/src/transport.ts`
3. `sdks/js/src/logger.ts`
4. `sdks/js/src/crash.ts`
5. `sdks/js/src/analytics.ts`
6. `sdks/js/src/index.ts`
7. Build + bundle check

### Phase 4 — Documentation
1. `docs/integration-flutter.md` — guide 5 minutes pour intégrer dans Panda ou autre app Flutter
2. `docs/integration-web.md` — guide JS/TS
3. Mettre à jour le README principal

---

## 9. Décisions d'architecture clés

| Décision | Choix | Raison |
|---|---|---|
| Proxy language | Go | Latence faible, binaire single, facile à Dockeriser |
| Pas de modification OpenObserve | ✅ | AGPL-3.0 compliance, upgrades faciles |
| Sentry-compatible plutôt que GlitchTip | ✅ | `sentry_flutter` fonctionne direct avec le proxy |
| PostHog-compatible pour analytics | ✅ | SDK mature, riche en features |
| SDK Dart from scratch (pas wrapper sentry_flutter) | ✅ | Contrôle complet, pas de dépendance externe |
| Batch + retry côté SDK | ✅ | Résilience réseau mobile |

---

## 10. URLs API une fois déployé

```
OpenObserve dashboard : http://your-server:5080
Argos ingest proxy    : http://your-server:9999

# Pour sentry_flutter DSN :
dsn: http://any-key@your-server:9999/api/panda-ide

# Pour analytics Dart SDK :
url: http://your-server:9999

# Pour OTEL exporters :
endpoint: http://your-server:9999/v1/traces
```

---

*Généré le 2026-08-04 par Replit Agent — Panda IDE project*
