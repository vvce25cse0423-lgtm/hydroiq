# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Supabase / Ktor
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**

# Health Connect
-keep class androidx.health.connect.** { *; }
-dontwarn androidx.health.connect.**

# WorkManager
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class ** {
    @kotlinx.serialization.SerialName <fields>;
}

# Gson / JSON models
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# App models
-keep class com.hydroiq.app.data.** { *; }
-keep class com.hydroiq.app.health.** { *; }

# WorkManager background entry point
-keep class com.hydroiq.app.worker.** { *; }

# Flutter local notifications
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# OkHttp (used by Ktor)
-dontwarn okhttp3.**
-dontwarn okio.**

# Audioplayers
-dontwarn xyz.luan.audioplayers.**
-keep class xyz.luan.audioplayers.** { *; }

# Printing / PDF
-dontwarn net.nfet.flutter.printing.**
-keep class net.nfet.flutter.printing.** { *; }

# Permissions / Location
-dontwarn com.baseflow.permissionhandler.**
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.geolocator.**
-keep class com.baseflow.geolocator.** { *; }

# Speech to text
-dontwarn com.csdcorp.speech_to_text.**
-keep class com.csdcorp.speech_to_text.** { *; }

# General plugins
-dontwarn dev.fluttercommunity.plus.**
-dontwarn crazecoder.openfile.**

# Home Widget
-dontwarn es.antonborri.home_widget.**
-keep class es.antonborri.home_widget.** { *; }
-keep class com.hydroiq.app.widget.** { *; }
