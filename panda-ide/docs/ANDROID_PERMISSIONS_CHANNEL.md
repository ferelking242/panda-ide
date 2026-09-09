# ⚠️ Permissions Android & Extensions — Le point crucial

## La vérité technique

> **Une extension ne peut JAMAIS obtenir une permission que l'APK hôte
> n'a pas déclarée dans son AndroidManifest.xml.**

C'est le modèle de sécurité Android : les runtime permissions sont un
sous-ensemble strict de ce qui est déclaré dans le manifest.

| Situation | Résultat |
|---|---|
| App déclare CAMERA + extension demande | ✅ Boîte système → accordée à l'extension |
| App NE déclare PAS CAMERA + extension demande | ❌ Refus silencieux immédiat, aucune boîte |

**Mais déclarer ≠ accorder.** Déclarer une permission dans le manifest
ne donne AUCUN accès : l'accès n'existe qu'après le consentement runtime
de l'utilisateur (la boîte système). Donc :

- L'app peut déclarer camera/micro/contacts sans jamais les utiliser elle-même
- Chaque extension doit obtenir le consentement via notre broker
  (`ExtensionPermissionManager`) AVANT d'y toucher
- Révoquer = supprimer l'extension → grants supprimés

## À ajouter dans `android/app/src/main/AndroidManifest.xml`

```xml
<!-- ── Permissions pour extensions (déclarées, jamais utilisées par l'app) ── -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.READ_CONTACTS" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.READ_PHONE_STATE" />
```

## Handler natif à ajouter (MainActivity.kt)

```kotlin
private var pendingPermissionResult: MethodChannel.Result? = null
private val PERMISSION_CODE = 4711
private lateinit var permissionChannel: MethodChannel

// Dans configureFlutterEngine(flutterEngine):
permissionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
                                  "panda.ide.permissions")
permissionChannel.setMethodCallHandler { call, result ->
    when (call.method) {
        "requestPermission" -> {
            val perm = call.argument<String>("permission")!!
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(this, arrayOf(perm), PERMISSION_CODE)
        }
        else -> result.notImplemented()
    }
}

// Canal intents (redirections)
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "panda.ide.intents")
    .setMethodCallHandler { call, result ->
        try {
            when (call.method) {
                "openUrl" -> {
                    startActivity(Intent(Intent.ACTION_VIEW,
                        Uri.parse(call.argument<String>("url"))))
                    result.success(true)
                }
                "openSettings" -> {
                    startActivity(Intent(call.argument<String>("action")))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("INTENT", e.message, null) }
    }

override fun onRequestPermissionsResult(
    requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == PERMISSION_CODE) {
        pendingPermissionResult?.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
        pendingPermissionResult = null
    }
}
```

## Chaîne complète de consentement

```
Extension demande 'camera'
  → ExtensionPermissionManager.request()
     ├─ déjà accordée ? → ✅ direct
     ├─ Dialog rationale (notre UI, nom ext + usage)
     └─ accepté → MethodChannel → boîte système Android
          ├─ accordé   → grant persisté JSON → ✅
          └─ refusé    → PermissionResult.denied
```

L'app seule ne touche JAMAIS caméra/micro : seules les extensions,
avec double consentement (rationale + boîte système), y accèdent.
