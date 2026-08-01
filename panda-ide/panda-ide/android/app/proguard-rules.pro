-keep class com.write4me.llama_flutter_android.** { *; }

-keep class kotlin.jvm.functions.Function1
-keepclassmembers class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}

-keep class com.write4me.llama_flutter_android.LlamaFlutterAndroidPlugin$* { *; }

-keepclasseswithmembernames class * {
    native <methods>;
}