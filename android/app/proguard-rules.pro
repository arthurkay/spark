# Flutter-specific ProGuard rules

# Keep Flutter wrapper classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep annotation processing
-keepattributes *Annotation*

# Keep Dio and related classes (for networking)
-keep class com.squareup.okhttp3.** { *; }
-keep class com.squareup.okhttp.** { *; }
-dontwarn com.squareup.okhttp3.**
-dontwarn com.squareup.okhttp.**
-keep class io.flutter.plugins.** { *; }

# Keep flutter_secure_storage (platform channels)
-keep class com.it_nomads.flutter_secure_storage.** { *; }

# Keep flutter_local_notifications (platform channels)
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Keep web_socket_channel
-keep class io.flutter.plugins.web_socket_channel.** { *; }

# Keep xterm terminal emulator
-keep class com.xterm.** { *; }

# Keep flutter_svg (dynamic class loading)
-keep class com.flutter_svg.** { *; }

# Keep models for JSON serialization
-keep class zm.co.cloud.spark.core.models.** { *; }

# Play Store split APK classes (referenced but not always available)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
