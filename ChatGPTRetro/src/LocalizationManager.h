#import <Foundation/Foundation.h>

extern NSString *const kLanguageDidChangeNotification;

typedef NS_ENUM(NSInteger, AppLanguage) {
    AppLanguageAuto = 0, // Cihaz Diline Göre Otomatik
    AppLanguageTurkish = 1,
    AppLanguageEnglish = 2
};

@interface LocalizationManager : NSObject

@property (nonatomic, assign) AppLanguage selectedLanguage;

+ (instancetype)sharedManager;
- (BOOL)isTurkish;
- (NSString *)stringForKey:(NSString *)key;

@end

// Kolay erişim makrosu
#define LocalizedString(key) [[LocalizationManager sharedManager] stringForKey:(key)]
