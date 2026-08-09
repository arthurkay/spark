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
-keep class io.flutter.plugins.** { *; }

# Keep models for JSON serialization
-keep class zm.co.cloud.spark.core.models.** { *; }

# Play Store split APK classes (referenced but not always available)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
