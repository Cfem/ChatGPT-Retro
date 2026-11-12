#import "LocalizationManager.h"

NSString *const kLanguageDidChangeNotification = @"AppLanguageDidChangeNotification";
static NSString *const kAppLanguageDefaultsKey = @"AppSelectedLanguageSetting";

@interface LocalizationManager ()
@property (nonatomic, strong) NSDictionary *trDict;
@property (nonatomic, strong) NSDictionary *enDict;
@end

@implementation LocalizationManager

+ (instancetype)sharedManager {
    static LocalizationManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LocalizationManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _selectedLanguage = [[NSUserDefaults standardUserDefaults] integerForKey:kAppLanguageDefaultsKey];
        [self setupDictionaries];
    }
    return self;
}

- (void)setSelectedLanguage:(AppLanguage)selectedLanguage {
    _selectedLanguage = selectedLanguage;
    [[NSUserDefaults standardUserDefaults] setInteger:selectedLanguage forKey:kAppLanguageDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kLanguageDidChangeNotification object:nil];
}

- (BOOL)isTurkish {
    if (self.selectedLanguage == AppLanguageTurkish) return YES;
    if (self.selectedLanguage == AppLanguageEnglish) return NO;

    // Otomatik: Cihazın tercih edilen ilk diline bak
    NSArray *langs = [NSLocale preferredLanguages];
    NSString *current = langs.firstObject ?: @"en";
    return [current hasPrefix:@"tr"];
}

- (void)setupDictionaries {
    _trDict = @{
        @"app_title": @"ChatGPT",
        @"sidebar_chats": @"☰ Sohbetler",
        @"settings_title": @"Ayarlar",
        @"new_chat_button": @"＋ Yeni Sohbet Başlat",
        @"new_chat_title": @"Yeni Sohbet",
        @"input_placeholder": @"Mesajınızı yazın...",
        @"send_button": @"Gönder",
        @"save_button": @"Kaydet",
        @"close_button": @"Kapat",
        @"saved_alert_title": @"Kaydedildi",
        @"saved_alert_msg": @"Ayarlar başarıyla kaydedildi!",
        @"ok_button": @"Tamam",
        @"cancel_button": @"Vazgeç",
        @"history_title": @"Geçmiş Sohbetler",
        @"msg_count_format": @"%lu mesaj • %@",
        @"section_siwc": @"SIGN IN WITH CHATGPT (PLAN KULLANIMI)",
        @"section_model": @"CHATGPT MODELİ",
        @"section_instructions": @"ÖZEL SİSTEM TALİMATI & BELLEK",
        @"section_apikey": @"OPENAI API ANAHTARI (OPSİYONEL)",
        @"section_language": @"DİL SEÇENEĞİ (LANGUAGE)",
        @"section_system": @"SİSTEM BİLGİSİ",
        @"siwc_login_btn": @"🟢 Continue with ChatGPT (Safari/QR)",
        @"siwc_manual_btn": @"🔗 Doğrulama Linkini Manuel Yapıştır",
        @"siwc_connected": @"🟢 Connected",
        @"siwc_status": @"Durum",
        @"siwc_enabled": @"ChatGPT plan usage is enabled",
        @"siwc_identity_only": @"Identity only",
        @"siwc_manage": @"📊 Manage usage (chatgpt.com/settings/usage)",
        @"siwc_disconnect": @"🔴 Bağlantıyı Kes (Disconnect)",
        @"fetch_models_btn": @"🔄 Modelleri Canlı Güncelle",
        @"fetching_models": @"Modeller taranıyor...",
        @"lang_auto": @"Otomatik (Cihaz Dili)",
        @"lang_tr": @"Türkçe",
        @"lang_en": @"English",
        @"instructions_placeholder": @"ChatGPT'nin sizi nasıl tanımasını istediğinizi yazın...",
        @"instructions_footer": @"ChatGPT'nin sizi tanıması ve bağlamınızı hiç unutmamasını istediğiniz bilgileri buraya yazın. Tüm sohbetlerde otomatik uygulanır.",
        @"welcome_msg": @"👋 ChatGPT Retro'ya Hoş Geldiniz!\n\nBu uygulama iPad Mini 1 (iOS 8.4) üzerinde resmi OpenAI modelleriyle doğrudan sohbet etmeniz için uyarlandı.\n\n💬 Sol üstteki '☰ Sohbetler' menüsünden geçmiş konuşmalarınıza ulaşabilir, sağdan 'Ayarlar' çekmecesini açabilirsiniz.",
        @"auth_prompt_title": @"ChatGPT Girişi Gerekli",
        @"auth_prompt_msg": @"ChatGPT ile konuşabilmek için ChatGPT hesabınızla giriş yapabilir veya Ayarlar'dan API Anahtarı girebilirsiniz.",
        @"auth_prompt_login": @"ChatGPT ile Giriş Yap (QR / Telefon)",
        @"auth_prompt_settings": @"Ayarlar'ı Aç",
        @"auth_status_ready": @" [Hazır]",
        @"auth_status_need_login": @" [Giriş Gerekli]",
        @"auth_status_plan": @" [ChatGPT Planı]"
    };

    _enDict = @{
        @"app_title": @"ChatGPT",
        @"sidebar_chats": @"☰ Chats",
        @"settings_title": @"Settings",
        @"new_chat_button": @"＋ Start New Chat",
        @"new_chat_title": @"New Chat",
        @"input_placeholder": @"Type a message...",
        @"send_button": @"Send",
        @"save_button": @"Save",
        @"close_button": @"Close",
        @"saved_alert_title": @"Saved",
        @"saved_alert_msg": @"Settings successfully saved!",
        @"ok_button": @"OK",
        @"cancel_button": @"Cancel",
        @"history_title": @"Chat History",
        @"msg_count_format": @"%lu messages • %@",
        @"section_siwc": @"SIGN IN WITH CHATGPT (PLAN USAGE)",
        @"section_model": @"CHATGPT MODEL",
        @"section_instructions": @"CUSTOM SYSTEM INSTRUCTIONS & MEMORY",
        @"section_apikey": @"OPENAI API KEY (OPTIONAL)",
        @"section_language": @"LANGUAGE SELECTION",
        @"section_system": @"SYSTEM INFO",
        @"siwc_login_btn": @"🟢 Continue with ChatGPT (Safari/QR)",
        @"siwc_manual_btn": @"🔗 Paste Verification URL Manually",
        @"siwc_connected": @"🟢 Connected",
        @"siwc_status": @"Status",
        @"siwc_enabled": @"ChatGPT plan usage is enabled",
        @"siwc_identity_only": @"Identity only",
        @"siwc_manage": @"📊 Manage usage (chatgpt.com/settings/usage)",
        @"siwc_disconnect": @"🔴 Disconnect Account",
        @"fetch_models_btn": @"🔄 Fetch Live Models",
        @"fetching_models": @"Fetching models...",
        @"lang_auto": @"Automatic (System Language)",
        @"lang_tr": @"Türkçe",
        @"lang_en": @"English",
        @"instructions_placeholder": @"Tell ChatGPT what you want it to remember about you...",
        @"instructions_footer": @"Information you want ChatGPT to remember across all your conversations (name, background, preferred response tone, etc.).",
        @"welcome_msg": @"👋 Welcome to ChatGPT Retro!\n\nAdapted for iPad Mini 1 (iOS 8.4) to chat directly with OpenAI models.\n\n💬 Access past chats from the '☰ Chats' menu on the left, or open 'Settings' on the right.",
        @"auth_prompt_title": @"ChatGPT Authentication Required",
        @"auth_prompt_msg": @"Please sign in with your ChatGPT account or enter an OpenAI API key in Settings to continue.",
        @"auth_prompt_login": @"Sign In with ChatGPT (QR / Phone)",
        @"auth_prompt_settings": @"Open Settings",
        @"auth_status_ready": @" [Ready]",
        @"auth_status_need_login": @" [Login Required]",
        @"auth_status_plan": @" [ChatGPT Plan]"
    };
}

- (NSString *)stringForKey:(NSString *)key {
    BOOL tr = [self isTurkish];
    NSDictionary *target = tr ? self.trDict : self.enDict;
    NSString *val = target[key];
    if (val) return val;
    // Fallback to English dictionary
    return self.enDict[key] ?: key;
}

@end
