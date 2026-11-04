# Keep the Accessibility service (instantiated by the system via reflection)
-keep class com.android.shell.ghost.** { *; }
-keep class com.android.shell.ghost.GhostAccessibilityService { *; }
-keep class com.android.shell.ghost.BootReceiver { *; }
-keep class com.android.shell.ghost.TransparentActivity { *; }
-keepclassmembers class * extends android.app.Service { *; }
-keepclassmembers class * extends android.content.BroadcastReceiver { *; }
-keepclassmembers class * extends android.view.accessibility.AccessibilityService { *; }