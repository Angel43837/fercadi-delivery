-keep class io.flutter.** { *; }
-keep class com.google.** { *; }
-dontwarn com.google.**

# Stripe PushProvisioning (optional feature — not used in this app)
-dontwarn com.stripe.android.pushProvisioning.**
-keep class com.stripe.android.pushProvisioning.** { *; }
