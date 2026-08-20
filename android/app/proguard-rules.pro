# Flutter + R8 minification rules
# Keep Flutter engine and plugin classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Llama native plugin
-keep class com.write4me.llama_flutter_android.** { *; }
-keep class com.write4me.llama_flutter_android.LlamaFlutterAndroidPlugin$* { *; }

# Keep Shizuku
-keep class dev.rikka.shizuku.** { *; }

# Keep Play Core / Feature delivery
-keep class com.google.android.play.** { *; }
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.appupdate.**

# Keep MethodChannel-bridged classes (all plugins use them)
-keepclassmembers class * {
    @io.flutter.plugin.common.MethodChannel.Method *;
}

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Flutter SharedPreferences plugin
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Flutter path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# Don't strip stack traces from exceptions
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Keep classes referenced by reflection
-keepclassmembers class * extends android.app.Activity {
    public void *(android.view.View);
}
