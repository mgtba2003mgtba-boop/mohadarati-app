# 📱 دليل نشر تطبيق الكلية الجامعي (NUST Student Portal)
### للنشر على متجر Google Play ومتجر Apple App Store

---

## 🏛️ نظرة عامة
تطبيق **بوابة الطالب الأكاديمية (NUST)** مبني باستخدام **Flutter 3.47** ومصمم ليعمل بكفاءة عالية على منصتي **Android** و **iOS**.

---

## 🤖 أولاً: خطوات بناء ونشر التطبيق على Google Play Store

### 1. إعداد مفتاح التوقيع (Keystore):
قم بتوليد مفتاح توقيع التطبيق عبر الأمر التالي في الطرفية:
```bash
keytool -genkey -v -keystore nust-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias nust_key
```

### 2. تهيئة ملف `key.properties`:
أنشئ ملفاً باسم `android/key.properties` يحتوي على:
```properties
storePassword=كلمة_المرور_التي_اخترتها
keyPassword=كلمة_المرور_التي_اخترتها
keyAlias=nust_key
storeFile=../nust-release.jks
```

### 3. بناء حزمة أندرويد الرسمية (AAB):
```bash
flutter build appbundle --release
```
* الملف الناتج: `build/app/outputs/bundle/release/app-release.aab`
* هذا الملف هو المطلوب رفعه مباشرة إلى **Google Play Console** تحت بند Production أو Open Testing.

---

## 🍎 ثانياً: خطوات بناء ونشر التطبيق على Apple App Store

### 1. المتطلبات:
* حساب مطور في Apple Developer Program ($99/سنة).
* جهاز Mac مزود ببرنامج Xcode (أو استخدام خدمات سحابية مثل Codemagic / GitHub Actions).

### 2. تثبيت التبعيات وبناء مشروع iOS:
```bash
cd ios
pod install
cd ..
flutter build ipa --release
```

### 3. رفع التطبيق إلى App Store Connect:
* يمكنك فتح مجلد `ios/Runner.xcworkspace` في Xcode.
* من قائمة `Product` اختر `Archive`.
* اضغط على `Distribute App` واختر `App Store Connect` ليتم الرفع تلقائياً عبر TestFlight ثم إرساله للمراجعة.

---

## ⚡ ثالثاً: كيفية تشغيل التطبيق في وضع التطوير المحلي
```bash
flutter run
```
* يدعم التطبيق أجهزة Android المادية، المحاكيات (Emulators)، وهواتف iPhone.
