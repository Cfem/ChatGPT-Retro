# RetroGemini iOS 8 (iPad Mini 1 Client)

RetroGemini, Apple A5 çipli ve 512 MB RAM'e sahip **iPad Mini 1 (iOS 8.4)** cihazlar için özel olarak tasarlanmış, ultra hafif ve optimize edilmiş modern bir **Google Gemini AI** istemcisidir.

![Target](https://img.shields.io/badge/Target-iOS%208.4%20(iPad%20Mini%201)-blue)
![Architecture](https://img.shields.io/badge/Arch-armv7%20(32--bit)-orange)
![Size](https://img.shields.io/badge/Size-33%20KB%20(.ipa)-green)

---

## 🌟 Özellikler

1. **Modern Gemini Modelleri:**
   - `gemini-1.5-flash` (Hızlı, akıllı ve önerilen varsayılan model)
   - `gemini-1.5-flash-8b` (512 MB RAM ve düşük gecikme için ultra hafif model)
   - `gemini-1.5-pro` (Kapsamlı mantıksal sorgular için)

2. **Dönemin Orijinal iOS 8 Tasarım Dili:**
   - iMessage tarzı yuvarlatılmış konuşma balonları (Kullanıcı için iOS 8 Mavisi `#007AFF`, Gemini için Açık Gri `#E5E5EA`).
   - Yarı saydam (translucent) üst navigasyon çubuğu ve ince sınır çizgileri (0.5pt single-pixel separator).
   - `HelveticaNeue` tipografisi.
   - Klavyeyle tam senkronize hareket eden yumuşak yay animasyonlu giriş çubuğu.

3. **512 MB RAM ve Apple A5 İçin Ekstrem Optimizasyon:**
   - **Sıfır WebView:** Bellek katili olan UIWebView / WKWebView yerine %100 yerel UIKit ve TextKit.
   - **Manuel Frame Layout:** A5 işlemciye yük bindiren AutoLayout yerine el ile hesaplanan ultra hızlı frame yerleşimi (60 FPS kaydırma).
   - **Hücre Yüksekliği Önbellekleme (Height Caching):** Mesaj yükseklikleri bir kez hesaplanır, tekrar render edilmez.
   - **Bağlam Limiti (Context Pruning):** Belleği korumak için sadece son konuşma geçmişi API'ye iletilir.

4. **Doğrudan Google AI Studio Entegrasyonu:**
   - Ücretli abonelik veya kredi kartı gerektirmeden, [Google AI Studio](https://aistudio.google.com/) üzerinden alınan ücretsiz API Key ile çalışır.
   - Anahtar cihazın yerel `NSUserDefaults` deposunda saklanır.

---

## 📲 iPad Mini 1'e Kurulum (.IPA Yükleme)

Cihazınız jailbreakli olduğu için `GeminiRetro.ipa` dosyasını kurmak çok kolaydır:

### Yöntem 1: Filza File Manager ile (Doğrudan iPad üzerinden)
1. `GeminiRetro.ipa` dosyasını AirDrop, Google Drive veya yerel ağ üzerinden iPad'e aktarın.
2. iPad'inizdeki **Filza** uygulamasını açın.
3. `GeminiRetro.ipa` dosyasına dokunun ve sağ üstteki **"Yükle" (Install)** butonuna basın.
4. Kurulum saniyeler içinde tamamlanır ve ana ekrana **Gemini** ikonu gelir.

### Yöntem 2: Sideloadly veya Apple Configurator / 3uTools ile (Mac/PC üzerinden)
1. iPad'inizi kabloyla bilgisayarınıza bağlayın.
2. Sideloadly veya 3uTools açıp `GeminiRetro.ipa` dosyasını sürükleyip bırakın ve yükleyin.

*(Not: Cihazınızda Cydia'dan **AppSync Unified** tweak'inin kurulu olduğundan emin olun).*

---

## 🛠️ Yeniden Derleme (Build from Source)

Tüm ortam ve araçlar proje klasörüne lokal olarak kurulmuştur. Yeniden derlemek için sadece şu komutu çalıştırmanız yeterlidir:

```bash
make ipa
```

Derleme tamamlandığında dizinde doğrudan `GeminiRetro.ipa` oluşacaktır.
