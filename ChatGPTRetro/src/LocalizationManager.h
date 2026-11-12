#import <Foundation/Foundation.h>

extern NSString *const kLanguageDidChangeNotification;

typedef NS_ENUM(NSInteger, AppLanguage) {
    AppLanguageAuto = 0, // Cihaz Diline Göre Otomatik (Automatic by device language)
    AppLanguageTurkish = 1,
    AppLanguageEnglish = 2
};

@interface LocalizationManager : NSObject

@property (nonatomic, assign) AppLanguage selectedLanguage;

+ (instancetype)sharedManager;
- (BOOL)isTurkish;
- (NSString *)stringForKey:(NSString *)key;

// Dinamik / genişletilebilir diller listesi (UIPickerView ve ayarlar için)
- (NSArray<NSDictionary *> *)availableLanguages;
- (NSString *)displayNameForLanguage:(AppLanguage)lang;

@end

// Kolay erişim makrosu
#define LocalizedString(key) [[LocalizationManager sharedManager] stringForKey:(key)]
