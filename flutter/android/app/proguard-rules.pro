# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in /usr/local/lib/android/sdk/build-tools/*/proguard-android.txt

-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.carriez.flutter_hbb.** { *; }
-keep class androidx.** { *; }

-dontwarn io.flutter.**
-dontwarn com.carriez.flutter_hbb.**

# Keep native methods and FFI entry points
-keepclasseswithmembers class * {
    native <methods>;
}
