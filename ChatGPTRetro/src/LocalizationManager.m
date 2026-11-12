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

- (NSArray<NSDictionary *> *)availableLanguages {
    return @[
        @{ @"code": @(AppLanguageAuto),    @"key": @"lang_auto" },
        @{ @"code": @(AppLanguageTurkish), @"key": @"lang_tr" },
        @{ @"code": @(AppLanguageEnglish), @"key": @"lang_en" }
    ];
}

- (NSString *)displayNameForLanguage:(AppLanguage)lang {
    for (NSDictionary *d in [self availableLanguages]) {
        if ([d[@"code"] integerValue] == lang) {
            return [self stringForKey:d[@"key"]];
        }
    }
    return @"Unknown";
}

- (void)setupDictionaries {
    _trDict = @{
        @"app_title": @"ChatGPT",
        @"sidebar_chats": @"☰ Sohbetler",
        @"settings_title": @"Ayarlar",
        @"new_chat_button": @"+ Yeni Sohbet",
        @"new_chat_title": @"Yeni Sohbet",
        @"input_placeholder": @"Mesajınızı yazın...",
        @"send_button": @"Gönder",
        @"save_button": @"Kaydet",
        @"close_button": @"Kapat",
        @"saved_alert_title": @"Kaydedildi",
        @"saved_alert_msg": @"Ayarlar başarıyla kaydedildi!",
        @"ok_button": @"Tamam",
        @"cancel_button": @"Vazgeç",
        @"delete_button": @"Sil",
        @"history_title": @"Geçmiş Sohbetler",
        @"msg_count_format": @"%lu mesaj • %@",
        @"section_siwc": @"CHATGPT İLE GİRİŞ YAP (HESAP / PLAN)",
        @"section_model": @"CHATGPT MODELİ",
        @"section_instructions": @"ÖZEL SİSTEM TALİMATI VE BELLEK",
        @"section_apikey": @"OPENAI API ANAHTARI (OPSİYONEL)",
        @"section_language": @"DİL SEÇENEĞİ",
        @"section_system": @"SİSTEM BİLGİSİ",
        @"language_label": @"Uygulama Dili",
        @"siwc_login_btn": @"ChatGPT ile Devam Et (Safari/QR)",
        @"siwc_manual_btn": @"Doğrulama Linkini Manuel Yapıştır",
        @"siwc_connected": @"Bağlandı",
        @"siwc_status": @"Durum",
        @"siwc_enabled": @"ChatGPT plan kullanımı devrede",
        @"siwc_identity_only": @"Yalnızca kimlik",
        @"siwc_manage": @"Kullanımı Yönet (chatgpt.com)",
        @"siwc_disconnect": @"Hesap Bağlantısını Kes",
        @"fetch_models_btn": @"Modelleri Canlı Güncelle",
        @"fetching_models": @"Modeller taranıyor...",
        @"lang_auto": @"Otomatik (Cihaz Dili)",
        @"lang_tr": @"Türkçe",
        @"lang_en": @"English",
        @"instructions_placeholder": @"ChatGPT'nin sizi nasıl tanımasını istediğinizi ve bağlamı buraya yazın...",
        @"instructions_footer": @"Aktif (işaretli) sistem talimatları tüm sohbetlere otomatik eklenir. İstediğinizi ekleyip çıkarabilir veya solundaki tiki kapatabilirsiniz.",
        @"add_prompt_button": @"+ Yeni Talimat Ekle",
        @"add_prompt_title": @"Yeni Sistem Talimatı",
        @"edit_prompt_title": @"Talimatı Düzenle",
        @"prompt_title_placeholder": @"Başlık (Örn: Tıp Fakültesi / Python Uzmanı)",
        @"prompt_content_placeholder": @"Talimat içeriğini yazın...",
        @"welcome_msg": @"ChatGPT Retro'ya Hoş Geldiniz!\n\nBu uygulama iPad Mini 1 (iOS 8.4) üzerinde resmi OpenAI modelleriyle doğrudan sohbet etmeniz için hazırlandı.\n\nSol üstteki 'Sohbetler' menüsünden geçmiş konuşmalarınıza ulaşabilir, sağ üstteki dişli simgesinden ayarları açabilirsiniz.",
        @"auth_prompt_title": @"Giriş Yapılması Gerekli",
        @"auth_prompt_msg": @"ChatGPT ile konuşabilmek için ChatGPT hesabınızla giriş yapabilir veya Ayarlar'dan API Anahtarı girebilirsiniz.",
        @"auth_prompt_login": @"ChatGPT ile Giriş Yap",
        @"auth_prompt_settings": @"Ayarları Aç",
        @"auth_status_ready": @" [Hazır]",
        @"auth_status_need_login": @" [Giriş Gerekli]",
        @"auth_status_plan": @" [ChatGPT Planı]",
        @"qr_step1_desc": @"1. iPhone veya modern cihazınızın kamerasıyla bu QR kodu okutup giriş yapın:",
        @"qr_copy_link": @"Giriş Linkini Panoya Kopyala",
        @"qr_step2_desc": @"2. Telefonda onaylayınca tarayıcının adres çubuğunda kalan yönlendirme linkini buraya yapıştırın:",
        @"qr_paste_btn": @"Panodan Yapıştır ve Girişi Tamamla",
        @"qr_safari_btn": @"iPad Safari'sinde Doğrudan Aç",
        @"model_label": @"Model",
        @"apikey_label": @"API Anahtarı",
        @"host_id_label": @"Cihaz Kimliği",
        @"version_label": @"Sürüm",
        @"section_capabilities": @"MODEL EK ÖZELLİKLERİ VE ARAÇLAR",
        @"cap_reasoning_effort": @"Düşünme Eforu (Reasoning)",
        @"cap_reasoning_summary": @"Düşünme Özeti (Summary)",
        @"cap_web_search": @"Canlı İnternet Araması",
        @"cap_code_interpreter": @"Python Kod Yorumlayıcı",
        @"cap_temperature": @"Yaratıcılık (Temperature)",
        @"effort_none": @"Yok (None)",
        @"effort_minimal": @"Minimal",
        @"effort_low": @"Düşük (Low)",
        @"effort_medium": @"Orta (Medium)",
        @"effort_high": @"Yüksek (High)",
        @"effort_xhigh": @"Çok Yüksek (xHigh)",
        @"effort_max": @"Maksimum (Max)",
        @"section_advanced": @"İLERİ SEVİYE AYARLAR",
        @"adv_screen_title": @"İleri Seviye Ayarlar",
        @"adv_menu_row": @"Maliyet ve Hafıza Optimizasyonu",
        @"advanced_footer": @"Bu ayarlar OpenAI API isteklerindeki girdi tokenlarını azaltarak harcamalarınızı ciddi oranda düşürür.",
        @"adv_prompt_caching_title": @"Prompt Caching",
        @"adv_prompt_caching_desc": @"Sistem talimatlarını ve geçmişi önbelleğe alarak OpenAI'ın %50-%80 indirimli tarifesini tetikler.",
        @"adv_truncate_assistant_title": @"Asistan Yanıtlarını Kırp",
        @"adv_truncate_assistant_desc": @"Geçmişteki uzun asistan mesajlarının orta kısmını kırparak gereksiz token gönderimini engeller.",
        @"adv_token_counter_title": @"Geçmiş Tur Limiti",
        @"adv_token_counter_desc": @"Modele gönderilecek geriye dönük mesaj sayısını sınırlar. Düşük değerler maliyeti önemli ölçüde azaltır.",
        @"turns_count_format": @"Son %ld Mesaj",
        @"adv_keyword_filtering_title": @"Anahtar Kelime Filtreleme",
        @"adv_keyword_filtering_desc": @"Yeni sorunuzla ortak kelimeler içeren geçmiş mesajları seçer, ilgisiz turları göndermez."
    };

    _enDict = @{
        @"app_title": @"ChatGPT",
        @"sidebar_chats": @"☰ Chats",
        @"settings_title": @"Settings",
        @"new_chat_button": @"+ New Chat",
        @"new_chat_title": @"New Chat",
        @"input_placeholder": @"Type a message...",
        @"send_button": @"Send",
        @"save_button": @"Save",
        @"close_button": @"Close",
        @"saved_alert_title": @"Saved",
        @"saved_alert_msg": @"Settings successfully saved!",
        @"ok_button": @"OK",
        @"cancel_button": @"Cancel",
        @"delete_button": @"Delete",
        @"history_title": @"Chat History",
        @"msg_count_format": @"%lu messages • %@",
        @"section_siwc": @"SIGN IN WITH CHATGPT (PLAN USAGE)",
        @"section_model": @"CHATGPT MODEL",
        @"section_instructions": @"CUSTOM SYSTEM INSTRUCTIONS & MEMORY",
        @"section_apikey": @"OPENAI API KEY (OPTIONAL)",
        @"section_language": @"LANGUAGE",
        @"section_system": @"SYSTEM INFO",
        @"language_label": @"App Language",
        @"siwc_login_btn": @"Continue with ChatGPT (Safari/QR)",
        @"siwc_manual_btn": @"Paste Verification URL Manually",
        @"siwc_connected": @"Connected",
        @"siwc_status": @"Status",
        @"siwc_enabled": @"ChatGPT plan usage is enabled",
        @"siwc_identity_only": @"Identity only",
        @"siwc_manage": @"Manage Usage (chatgpt.com)",
        @"siwc_disconnect": @"Disconnect Account",
        @"fetch_models_btn": @"Fetch Live Models",
        @"fetching_models": @"Fetching models...",
        @"lang_auto": @"Automatic (Device Language)",
        @"lang_tr": @"Türkçe",
        @"lang_en": @"English",
        @"instructions_placeholder": @"Tell ChatGPT what you want it to remember about you...",
        @"instructions_footer": @"Active (checked) system instructions are automatically applied to all chats. You can add, edit, or uncheck them.",
        @"add_prompt_button": @"+ Add New Instruction",
        @"add_prompt_title": @"New System Instruction",
        @"edit_prompt_title": @"Edit Instruction",
        @"prompt_title_placeholder": @"Title (e.g., Medical Student / Python Expert)",
        @"prompt_content_placeholder": @"Enter instruction text...",
        @"welcome_msg": @"Welcome to ChatGPT Retro!\n\nAdapted for iPad Mini 1 (iOS 8.4) to chat directly with OpenAI models.\n\nAccess past chats from the 'Chats' menu on the left, or open Settings via the gear icon on the right.",
        @"auth_prompt_title": @"Authentication Required",
        @"auth_prompt_msg": @"Please sign in with your ChatGPT account or enter an OpenAI API key in Settings to continue.",
        @"auth_prompt_login": @"Sign In with ChatGPT",
        @"auth_prompt_settings": @"Open Settings",
        @"auth_status_ready": @" [Ready]",
        @"auth_status_need_login": @" [Login Required]",
        @"auth_status_plan": @" [ChatGPT Plan]",
        @"qr_step1_desc": @"1. Scan this QR code with your iPhone or modern device camera to sign in:",
        @"qr_copy_link": @"Copy Sign In Link to Clipboard",
        @"qr_step2_desc": @"2. Once confirmed on your phone, paste the redirect URL from the browser address bar here:",
        @"qr_paste_btn": @"Paste from Clipboard and Complete",
        @"qr_safari_btn": @"Open Directly in iPad Safari",
        @"model_label": @"Model",
        @"apikey_label": @"API Key",
        @"host_id_label": @"Device ID",
        @"version_label": @"Version",
        @"section_capabilities": @"MODEL CAPABILITIES & TOOLS",
        @"cap_reasoning_effort": @"Reasoning Effort",
        @"cap_reasoning_summary": @"Reasoning Summary",
        @"cap_web_search": @"Live Web Search",
        @"cap_code_interpreter": @"Python Code Interpreter",
        @"cap_temperature": @"Creativity (Temperature)",
        @"effort_none": @"None",
        @"effort_minimal": @"Minimal",
        @"effort_low": @"Low",
        @"effort_medium": @"Medium",
        @"effort_high": @"High",
        @"effort_xhigh": @"xHigh",
        @"effort_max": @"Max",
        @"section_advanced": @"ADVANCED SETTINGS",
        @"adv_screen_title": @"Advanced Settings",
        @"adv_menu_row": @"Cost & Memory Optimizations",
        @"advanced_footer": @"These settings reduce input tokens on OpenAI API requests to significantly lower your bill.",
        @"adv_prompt_caching_title": @"Prompt Caching",
        @"adv_prompt_caching_desc": @"Caches system instructions and history to trigger OpenAI's 50%-80% discounted cache tariff.",
        @"adv_truncate_assistant_title": @"Truncate Assistant Responses",
        @"adv_truncate_assistant_desc": @"Trims middle portions of past long assistant messages to prevent redundant token transfer.",
        @"adv_token_counter_title": @"History Turns Limit",
        @"adv_token_counter_desc": @"Restricts how many prior turns are sent to the model. Lower values save significant token costs.",
        @"turns_count_format": @"Last %ld Turns",
        @"adv_keyword_filtering_title": @"Keyword Filtering",
        @"adv_keyword_filtering_desc": @"Picks past messages that share keywords with your new query, skipping unrelated turns."
    };
}

- (NSString *)stringForKey:(NSString *)key {
    BOOL tr = [self isTurkish];
    NSDictionary *target = tr ? self.trDict : self.enDict;
    NSString *val = target[key];
    if (val) return val;
    return self.enDict[key] ?: key;
}

@end
