#import "SettingsViewController.h"
#import "OpenAIClient.h"
#import "ChatGPTLoginModalViewController.h"
#import "LocalizationManager.h"
#import "AdvancedSettingsViewController.h"

@interface SettingsViewController () <ChatGPTLoginModalDelegate, UIPickerViewDataSource, UIPickerViewDelegate, UITextViewDelegate>

@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextView *systemInstructionTextView;
@property (nonatomic, strong) UITextField *languagePickerField;
@property (nonatomic, strong) UIPickerView *languagePicker;

// Dynamic Model Capability Controls (Section 3)
@property (nonatomic, strong) UISlider *reasoningEffortSlider;
@property (nonatomic, strong) UILabel *reasoningEffortValueLabel;
@property (nonatomic, strong) UISwitch *reasoningSummarySwitch;
@property (nonatomic, strong) UISlider *temperatureSlider;
@property (nonatomic, strong) UILabel *temperatureValueLabel;
@property (nonatomic, strong) UISwitch *webSearchSwitch;
@property (nonatomic, strong) UISwitch *codeInterpreterSwitch;

// Advanced Optimizations Controls (Section 6)
@property (nonatomic, strong) UISwitch *promptCachingSwitch;
@property (nonatomic, strong) UISwitch *truncateAssistantSwitch;
@property (nonatomic, strong) UISlider *tokenTurnsSlider;
@property (nonatomic, strong) UILabel *tokenTurnsValueLabel;
@property (nonatomic, strong) UISwitch *keywordFilteringSwitch;

@property (nonatomic, assign) BOOL isFetchingModels;
@property (nonatomic, assign) BOOL isSigningIn;

@end

@implementation SettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = LocalizedString(@"settings_title");

    // "Kapat" ve "Kaydet" butonları kaldırıldı (Dışarıya/karanlık alana dokunulduğunda otomatik kaydedilip kapanır)
    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.rightBarButtonItem = nil;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authStateDidChange:)
                                                 name:kChatGPTAuthStateDidChangeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(languageDidChange:)
                                                 name:kLanguageDidChangeNotification
                                               object:nil];

    [self setupFields];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.webSearchSwitch.on = [OpenAIClient sharedClient].enableWebSearch;
    [self.tableView reloadData];
}

- (void)languageDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.title = LocalizedString(@"settings_title");
        self.navigationItem.leftBarButtonItem.title = LocalizedString(@"close_button");
        self.navigationItem.rightBarButtonItem.title = LocalizedString(@"save_button");
        [self updateLanguageFieldText];
        [self updateReasoningEffortLabelText];
        [self.languagePicker reloadAllComponents];

        UIToolbar *tb = (UIToolbar *)self.languagePickerField.inputAccessoryView;
        if ([tb isKindOfClass:[UIToolbar class]] && tb.items.count > 1) {
            tb.items.lastObject.title = LocalizedString(@"ok_button");
        }

        [self.tableView reloadData];
    });
}

- (void)authStateDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isSigningIn = NO;
        [self.tableView reloadData];
        if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
            [self.delegate settingsDidUpdate];
        }
    });
}

- (void)setupFields {
    UIColor *openAIGreen = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];

    // 1. Language Picker Field & Accessory Toolbar (iOS classic bottom wheel, hidden trigger)
    _languagePicker = [[UIPickerView alloc] init];
    _languagePicker.dataSource = self;
    _languagePicker.delegate = self;

    _languagePickerField = [[UITextField alloc] initWithFrame:CGRectZero];
    _languagePickerField.hidden = YES;
    _languagePickerField.inputView = _languagePicker;

    UIToolbar *pickerToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    pickerToolbar.barStyle = UIBarStyleDefault;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneBtn = [[UIBarButtonItem alloc] initWithTitle:LocalizedString(@"ok_button")
                                                                style:UIBarButtonItemStyleDone
                                                               target:self
                                                               action:@selector(languagePickerDone)];
    pickerToolbar.items = @[flex, doneBtn];
    _languagePickerField.inputAccessoryView = pickerToolbar;
    [self.view addSubview:_languagePickerField];

    [self selectCurrentLanguageInPickerAnimated:NO];
    [self updateLanguageFieldText];

    // 2. API Key
    _apiKeyField = [[UITextField alloc] initWithFrame:CGRectZero];
    _apiKeyField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _apiKeyField.placeholder = @"sk-... (API Key)";
    _apiKeyField.text = [OpenAIClient sharedClient].apiKey;
    _apiKeyField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _apiKeyField.secureTextEntry = YES;
    _apiKeyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _apiKeyField.autocorrectionType = UITextAutocorrectionTypeNo;
    _apiKeyField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // 3. Model (Dinamik güncelleme için UIControlEventEditingChanged bağlı)
    _modelField = [[UITextField alloc] initWithFrame:CGRectZero];
    _modelField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _modelField.placeholder = @"gpt-4o-mini";
    _modelField.text = [OpenAIClient sharedClient].selectedModel;
    _modelField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _modelField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _modelField.autocorrectionType = UITextAutocorrectionTypeNo;
    _modelField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _modelField.delegate = self;
    [_modelField addTarget:self action:@selector(modelFieldEditingChanged:) forControlEvents:UIControlEventEditingChanged];

    // 4. Custom System Instructions
    _systemInstructionTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    _systemInstructionTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _systemInstructionTextView.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _systemInstructionTextView.backgroundColor = [UIColor clearColor];
    _systemInstructionTextView.text = [OpenAIClient sharedClient].customSystemInstruction;

    // 5. Dynamic Model Capability Controls (Sliders & Switches)
    _reasoningEffortSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _reasoningEffortSlider.minimumValue = 0.0f;
    _reasoningEffortSlider.maximumValue = 6.0f;
    _reasoningEffortSlider.continuous = YES;
    _reasoningEffortSlider.minimumTrackTintColor = openAIGreen;
    _reasoningEffortSlider.value = (float)[OpenAIClient sharedClient].reasoningEffortLevel;
    [_reasoningEffortSlider addTarget:self action:@selector(reasoningEffortSliderChanged:) forControlEvents:UIControlEventValueChanged];

    _reasoningEffortValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _reasoningEffortValueLabel.textAlignment = NSTextAlignmentRight;
    _reasoningEffortValueLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:13.0];
    _reasoningEffortValueLabel.textColor = openAIGreen;
    [self updateReasoningEffortLabelText];

    _reasoningSummarySwitch = [[UISwitch alloc] init];
    _reasoningSummarySwitch.onTintColor = openAIGreen;
    _reasoningSummarySwitch.on = [OpenAIClient sharedClient].enableReasoningSummary;
    [_reasoningSummarySwitch addTarget:self action:@selector(reasoningSummarySwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _temperatureSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _temperatureSlider.minimumValue = 0.0f;
    _temperatureSlider.maximumValue = 2.0f;
    _temperatureSlider.continuous = YES;
    _temperatureSlider.minimumTrackTintColor = openAIGreen;
    _temperatureSlider.value = [OpenAIClient sharedClient].modelTemperature;
    [_temperatureSlider addTarget:self action:@selector(temperatureSliderChanged:) forControlEvents:UIControlEventValueChanged];

    _temperatureValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _temperatureValueLabel.textAlignment = NSTextAlignmentRight;
    _temperatureValueLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:13.0];
    _temperatureValueLabel.textColor = openAIGreen;
    _temperatureValueLabel.text = [NSString stringWithFormat:@"%.1f", [OpenAIClient sharedClient].modelTemperature];

    _webSearchSwitch = [[UISwitch alloc] init];
    _webSearchSwitch.onTintColor = openAIGreen;
    _webSearchSwitch.on = [OpenAIClient sharedClient].enableWebSearch;
    [_webSearchSwitch addTarget:self action:@selector(webSearchSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _codeInterpreterSwitch = [[UISwitch alloc] init];
    _codeInterpreterSwitch.onTintColor = openAIGreen;
    _codeInterpreterSwitch.on = [OpenAIClient sharedClient].enableCodeInterpreter;
    [_codeInterpreterSwitch addTarget:self action:@selector(codeInterpreterSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    // 6. Advanced Cost Optimization Controls
    _promptCachingSwitch = [[UISwitch alloc] init];
    _promptCachingSwitch.onTintColor = openAIGreen;
    _promptCachingSwitch.on = [OpenAIClient sharedClient].enablePromptCaching;
    [_promptCachingSwitch addTarget:self action:@selector(promptCachingSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _truncateAssistantSwitch = [[UISwitch alloc] init];
    _truncateAssistantSwitch.onTintColor = openAIGreen;
    _truncateAssistantSwitch.on = [OpenAIClient sharedClient].enableTruncateAssistant;
    [_truncateAssistantSwitch addTarget:self action:@selector(truncateAssistantSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _keywordFilteringSwitch = [[UISwitch alloc] init];
    _keywordFilteringSwitch.onTintColor = openAIGreen;
    _keywordFilteringSwitch.on = [OpenAIClient sharedClient].enableKeywordFiltering;
    [_keywordFilteringSwitch addTarget:self action:@selector(keywordFilteringSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    // Eğer anahtar kelime açıksa asistan kırpma devre dışı olsun, ya da tam tersi
    [self updateAdvancedTogglesMutualExclusion];

    _tokenTurnsSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _tokenTurnsSlider.minimumValue = 1.0f;
    _tokenTurnsSlider.maximumValue = 20.0f;
    _tokenTurnsSlider.continuous = YES;
    _tokenTurnsSlider.minimumTrackTintColor = openAIGreen;
    _tokenTurnsSlider.value = (float)[OpenAIClient sharedClient].maxHistoryTurns;
    [_tokenTurnsSlider addTarget:self action:@selector(tokenTurnsSliderChanged:) forControlEvents:UIControlEventValueChanged];

    _tokenTurnsValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _tokenTurnsValueLabel.textAlignment = NSTextAlignmentRight;
    _tokenTurnsValueLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:13.0];
    _tokenTurnsValueLabel.textColor = openAIGreen;
    [self updateTokenTurnsLabelText];
}

#pragma mark - Dynamic Capability Actions

- (NSString *)activeModelString {
    NSString *m = [self.modelField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (m.length > 0) return m;
    return [OpenAIClient sharedClient].selectedModel ?: @"gpt-4o-mini";
}

- (NSArray<NSString *> *)capabilityRowTypesForCurrentModel {
    NSString *model = [self activeModelString];
    OpenAIClient *client = [OpenAIClient sharedClient];
    NSMutableArray *rows = [NSMutableArray array];

    if ([client supportsReasoningEffortForModel:model]) {
        [rows addObject:@"reasoning_effort"];
        [rows addObject:@"reasoning_summary"];
    } else if ([client supportsTemperatureForModel:model]) {
        [rows addObject:@"temperature"];
    }

    if ([client supportsWebSearchForModel:model]) {
        [rows addObject:@"web_search"];
    }
    if ([client supportsCodeInterpreterForModel:model]) {
        [rows addObject:@"code_interpreter"];
    }
    return rows;
}

- (void)modelFieldEditingChanged:(UITextField *)sender {
    [[OpenAIClient sharedClient] saveSelectedModel:sender.text];
    // Sadece 3. seksiyonu (Model Ek Özellikleri) dinamik yenile, klavyeyi kapatma
    [UIView performWithoutAnimation:^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationNone];
    }];
    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }
}

- (void)updateReasoningEffortLabelText {
    NSInteger level = (NSInteger)roundf(self.reasoningEffortSlider.value);
    NSArray *keys = @[@"effort_none", @"effort_minimal", @"effort_low", @"effort_medium", @"effort_high", @"effort_xhigh", @"effort_max"];
    if (level >= 0 && level < keys.count) {
        self.reasoningEffortValueLabel.text = LocalizedString(keys[level]);
    }
}

- (void)reasoningEffortSliderChanged:(UISlider *)sender {
    NSInteger snapped = (NSInteger)roundf(sender.value);
    [sender setValue:(float)snapped animated:NO];
    [OpenAIClient sharedClient].reasoningEffortLevel = snapped;
    [self updateReasoningEffortLabelText];
}

- (void)reasoningSummarySwitchChanged:(UISwitch *)sender {
    [OpenAIClient sharedClient].enableReasoningSummary = sender.isOn;
}

- (void)temperatureSliderChanged:(UISlider *)sender {
    float rounded = roundf(sender.value * 10.0f) / 10.0f;
    [OpenAIClient sharedClient].modelTemperature = rounded;
    self.temperatureValueLabel.text = [NSString stringWithFormat:@"%.1f", rounded];
}

- (void)webSearchSwitchChanged:(UISwitch *)sender {
    [OpenAIClient sharedClient].enableWebSearch = sender.isOn;
    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }
}

- (void)codeInterpreterSwitchChanged:(UISwitch *)sender {
    [OpenAIClient sharedClient].enableCodeInterpreter = sender.isOn;
}

#pragma mark - Advanced Optimizations Handlers

- (void)updateAdvancedTogglesMutualExclusion {
    if (self.keywordFilteringSwitch.isOn) {
        self.truncateAssistantSwitch.on = NO;
        self.truncateAssistantSwitch.enabled = NO;
        self.keywordFilteringSwitch.enabled = YES;
    } else if (self.truncateAssistantSwitch.isOn) {
        self.keywordFilteringSwitch.on = NO;
        self.keywordFilteringSwitch.enabled = NO;
        self.truncateAssistantSwitch.enabled = YES;
    } else {
        self.truncateAssistantSwitch.enabled = YES;
        self.keywordFilteringSwitch.enabled = YES;
    }
}

- (void)promptCachingSwitchChanged:(UISwitch *)sender {
    [OpenAIClient sharedClient].enablePromptCaching = sender.isOn;
}

- (void)truncateAssistantSwitchChanged:(UISwitch *)sender {
    [OpenAIClient sharedClient].enableTruncateAssistant = sender.isOn;
    [self updateAdvancedTogglesMutualExclusion];
}

- (void)keywordFilteringSwitchChanged:(UISwitch *)sender {
    [OpenAIClient sharedClient].enableKeywordFiltering = sender.isOn;
    [self updateAdvancedTogglesMutualExclusion];
}

- (void)updateTokenTurnsLabelText {
    NSInteger turns = (NSInteger)roundf(self.tokenTurnsSlider.value);
    NSString *format = LocalizedString(@"turns_count_format");
    self.tokenTurnsValueLabel.text = [NSString stringWithFormat:format, (long)turns];
}

- (void)tokenTurnsSliderChanged:(UISlider *)sender {
    NSInteger snapped = (NSInteger)roundf(sender.value);
    [sender setValue:(float)snapped animated:NO];
    [OpenAIClient sharedClient].maxHistoryTurns = snapped;
    [self updateTokenTurnsLabelText];
}

- (void)updateLanguageFieldText {
    _languagePickerField.text = [[LocalizationManager sharedManager] displayNameForLanguage:[LocalizationManager sharedManager].selectedLanguage];
}

- (void)selectCurrentLanguageInPickerAnimated:(BOOL)animated {
    NSArray *langs = [[LocalizationManager sharedManager] availableLanguages];
    AppLanguage current = [LocalizationManager sharedManager].selectedLanguage;
    for (NSInteger i = 0; i < langs.count; i++) {
        if ([langs[i][@"code"] integerValue] == current) {
            [self.languagePicker selectRow:i inComponent:0 animated:animated];
            break;
        }
    }
}

- (void)languagePickerDone {
    [self.languagePickerField resignFirstResponder];
}

#pragma mark - UIPickerView DataSource & Delegate

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return [[LocalizationManager sharedManager] availableLanguages].count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    NSArray *langs = [[LocalizationManager sharedManager] availableLanguages];
    if (row < langs.count) {
        NSString *key = langs[row][@"key"];
        return LocalizedString(key);
    }
    return @"";
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    NSArray *langs = [[LocalizationManager sharedManager] availableLanguages];
    if (row < langs.count) {
        AppLanguage selected = (AppLanguage)[langs[row][@"code"] integerValue];
        [LocalizationManager sharedManager].selectedLanguage = selected;
    }
}

- (void)closeButtonTapped {
    [self.view endEditing:YES];
    if ([self.delegate respondsToSelector:@selector(settingsDidRequestClose)]) {
        [self.delegate settingsDidRequestClose];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - System Prompts Actions (Apple Style List & Checkmark)

- (void)addNewPromptAction {
    [self.view endEditing:YES];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LocalizedString(@"add_prompt_title")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = LocalizedString(@"prompt_content_placeholder");
        textField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"ok_button") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *content = alert.textFields[0].text;
        if (content.length > 0) {
            NSMutableDictionary *newPrompt = [@{
                @"id": [[NSUUID UUID] UUIDString],
                @"content": content,
                @"enabled": @YES
            } mutableCopy];

            NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
            [list addObject:newPrompt];
            [[OpenAIClient sharedClient] saveSystemPromptsList:list];
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:4] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editPromptAtIndex:(NSInteger)index {
    NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
    if (index < 0 || index >= (NSInteger)list.count) return;

    NSMutableDictionary *item = list[index];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LocalizedString(@"edit_prompt_title")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = item[@"content"] ?: @"";
        textField.placeholder = LocalizedString(@"prompt_content_placeholder");
    }];

    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"ok_button") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *content = alert.textFields[0].text;
        if (content.length > 0) {
            item[@"content"] = content;
            [[OpenAIClient sharedClient] saveSystemPromptsList:list];
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:4] withRowAnimation:UITableViewRowAnimationNone];
        }
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)saveCurrentSettingsSilently {
    [self.view endEditing:YES];

    NSString *key = self.apiKeyField.text ?: @"";
    NSString *model = self.modelField.text ?: @"gpt-4o-mini";

    [[OpenAIClient sharedClient] saveApiKey:key];
    [[OpenAIClient sharedClient] saveSelectedModel:model];

    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }
}

- (void)saveSettingsAction {
    [self saveCurrentSettingsSilently];

    NSString *model = self.modelField.text ?: @"gpt-4o-mini";
    NSString *msg = [NSString stringWithFormat:@"%@\n\n• Model: %@", LocalizedString(@"saved_alert_msg"), model];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LocalizedString(@"saved_alert_title") message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"ok_button") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if ([self.delegate respondsToSelector:@selector(settingsDidRequestClose)]) {
            [self.delegate settingsDidRequestClose];
        } else {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)signInWithChatGPTAction {
    [self.view endEditing:YES];
    ChatGPTLoginModalViewController *modal = [[ChatGPTLoginModalViewController alloc] init];
    modal.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:modal];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)chatGPTLoginDidComplete {
    [self.tableView reloadData];
    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }
    NSString *email = [OpenAIClient sharedClient].userEmail ?: @"ChatGPT";
    [self showAlertWithTitle:LocalizedString(@"saved_alert_title")
                     message:[NSString stringWithFormat:@"%@: %@", LocalizedString(@"siwc_enabled"), email]];
}

- (void)pasteManualCallbackAction {
    [self.view endEditing:YES];
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:LocalizedString(@"siwc_manual_btn")
                                                                    message:@"http://127.0.0.1:8787/auth/callback?code=..."
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"http://127.0.0.1:8787/auth/callback?code=...";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [prompt addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
    [prompt addAction:[UIAlertAction actionWithTitle:LocalizedString(@"ok_button") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = prompt.textFields.firstObject.text ?: @"";
        if (text.length > 0) {
            [[OpenAIClient sharedClient] handleIncomingCallbackURLString:text completion:^(BOOL success, NSError *error) {
                [self.tableView reloadData];
                if (success) {
                    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                        [self.delegate settingsDidUpdate];
                    }
                    [self showAlertWithTitle:LocalizedString(@"saved_alert_title") message:LocalizedString(@"siwc_enabled")];
                } else {
                    [self showAlertWithTitle:@"Hata" message:error.localizedDescription];
                }
            }];
        }
    }]];
    [self presentViewController:prompt animated:YES completion:nil];
}

- (void)manageUsageAction {
    NSURL *usageUrl = [NSURL URLWithString:@"https://chatgpt.com/settings/usage"];
    if (usageUrl) {
        [[UIApplication sharedApplication] openURL:usageUrl];
    }
}

- (void)disconnectAccountAction {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:LocalizedString(@"siwc_disconnect")
                                                                     message:LocalizedString(@"siwc_disconnect")
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    [confirm addAction:[UIAlertAction actionWithTitle:LocalizedString(@"siwc_disconnect") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[OpenAIClient sharedClient] disconnectChatGPTAccountWithCompletion:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
                if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                    [self.delegate settingsDidUpdate];
                }
            });
        }];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
    confirm.popoverPresentationController.sourceView = self.view;
    confirm.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)refreshModelsAction {
    [self.view endEditing:YES];
    if (![[OpenAIClient sharedClient] isAuthenticated]) {
        [self showAlertWithTitle:LocalizedString(@"auth_prompt_title")
                         message:LocalizedString(@"auth_prompt_msg")];
        return;
    }

    self.isFetchingModels = YES;
    [self.tableView reloadData];

    [[OpenAIClient sharedClient] fetchAvailableModelsWithCompletion:^(NSArray *models, NSError *error) {
        self.isFetchingModels = NO;
        if (error) {
            [self showAlertWithTitle:@"Hata" message:error.localizedDescription];
            [self.tableView reloadData];
            return;
        }

        if (models.count == 0) {
            [self showAlertWithTitle:@"Hata" message:@"Model bulunamadı."];
            [self.tableView reloadData];
            return;
        }

        UIAlertController *picker = [UIAlertController alertControllerWithTitle:LocalizedString(@"section_model")
                                                                        message:nil
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];

        for (NSString *m in models) {
            [picker addAction:[UIAlertAction actionWithTitle:m style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                self.modelField.text = m;
                [[OpenAIClient sharedClient] saveSelectedModel:m];
                [self.tableView reloadData];
                if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                    [self.delegate settingsDidUpdate];
                }
            }]];
        }

        [picker addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
        picker.popoverPresentationController.sourceView = self.view;
        picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, 200, 1, 1);
        [self presentViewController:picker animated:YES completion:nil];
        [self.tableView reloadData];
    }];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"ok_button") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 8;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1; // Language selection
    if (section == 1) {
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            return 4; // Connected, Status, Manage, Disconnect
        }
        return 2; // Continue with ChatGPT, Paste URL
    }
    if (section == 2) return 2; // Model & Refresh Models
    if (section == 3) return [self capabilityRowTypesForCurrentModel].count; // Dynamic Model Capabilities
    if (section == 4) {
        // Sistem Talimatları Listesi + 1 satır ("+ Yeni Talimat Ekle")
        return [OpenAIClient sharedClient].systemPromptsList.count + 1;
    }
    if (section == 5) return 1; // API Key
    if (section == 6) return 1; // İleri Seviye Ayarlar alt sayfası butonu
    return 2; // System Info
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return LocalizedString(@"section_language");
    if (section == 1) return LocalizedString(@"section_siwc");
    if (section == 2) return LocalizedString(@"section_model");
    if (section == 3) return LocalizedString(@"section_capabilities");
    if (section == 4) return LocalizedString(@"section_instructions");
    if (section == 5) return LocalizedString(@"section_apikey");
    if (section == 6) return LocalizedString(@"section_advanced");
    return LocalizedString(@"section_system");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 4) return LocalizedString(@"instructions_footer");
    if (section == 6) return LocalizedString(@"advanced_footer");
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 3) {
        NSArray *rows = [self capabilityRowTypesForCurrentModel];
        if (indexPath.row < rows.count) {
            NSString *type = rows[indexPath.row];
            if ([type isEqualToString:@"reasoning_effort"] || [type isEqualToString:@"temperature"]) {
                return 74.0; // Slider + etiket satırı
            }
        }
        return 44.0;
    }
    if (indexPath.section == 4) {
        NSInteger promptCount = [OpenAIClient sharedClient].systemPromptsList.count;
        if (indexPath.row < promptCount) {
            NSDictionary *item = [OpenAIClient sharedClient].systemPromptsList[indexPath.row];
            NSString *content = item[@"content"] ?: @"";
            // iPad ekran genişliğine göre yazının tam yüksekliğini dinamik hesapla
            CGFloat cellW = tableView.bounds.size.width > 0 ? tableView.bounds.size.width : 500.0;
            CGFloat textW = cellW - 60.0; // Kenar boşlukları ve tik alanı
            CGRect rect = [content boundingRectWithSize:CGSizeMake(textW, CGFLOAT_MAX)
                                                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                             attributes:@{NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue" size:15.0]}
                                                context:nil];
            CGFloat calculatedH = ceilf(rect.size.height) + 24.0;
            return MAX(calculatedH, 44.0);
        }
        return 44.0; // "+ Yeni Talimat Ekle" satırı
    }
    return 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *extraKey = @"";
    if (indexPath.section == 3) {
        NSArray *rows = [self capabilityRowTypesForCurrentModel];
        if (indexPath.row < rows.count) extraKey = rows[indexPath.row];
    }
    NSString *cellId = [NSString stringWithFormat:@"Cell_%ld_%ld_%@_%d", (long)indexPath.section, (long)indexPath.row, extraKey, [[OpenAIClient sharedClient] isChatGPTAccountLinked]];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.text = nil;
    cell.textLabel.textColor = [UIColor blackColor];
    cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
    cell.detailTextLabel.text = nil;
    cell.detailTextLabel.textColor = [UIColor grayColor];

    for (UIView *sub in cell.contentView.subviews) {
        if (sub == self.reasoningEffortSlider || sub == self.reasoningEffortValueLabel ||
            sub == self.temperatureSlider || sub == self.temperatureValueLabel ||
            sub == self.modelField || sub == self.apiKeyField || sub == self.systemInstructionTextView ||
            sub == self.tokenTurnsSlider || sub == self.tokenTurnsValueLabel) {
            [sub removeFromSuperview];
        }
    }

    CGFloat w = tableView.bounds.size.width;
    UIColor *openAIGreen = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];

    if (indexPath.section == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.textLabel.text = LocalizedString(@"language_label");
        cell.detailTextLabel.text = [[LocalizationManager sharedManager] displayNameForLanguage:[LocalizationManager sharedManager].selectedLanguage];
        cell.detailTextLabel.textColor = openAIGreen;
        cell.detailTextLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            if (indexPath.row == 0) {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                NSString *email = [OpenAIClient sharedClient].userEmail;
                cell.textLabel.text = (email && email.length > 0) ? email : @"Hesap";
                cell.detailTextLabel.text = LocalizedString(@"siwc_connected");
                cell.detailTextLabel.textColor = openAIGreen;
            } else if (indexPath.row == 1) {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.textLabel.text = LocalizedString(@"siwc_status");
                cell.detailTextLabel.text = [OpenAIClient sharedClient].isPlanSharingEnabled
                    ? LocalizedString(@"siwc_enabled")
                    : LocalizedString(@"siwc_identity_only");
            } else if (indexPath.row == 2) {
                cell.textLabel.text = LocalizedString(@"siwc_manage");
                cell.textLabel.textColor = openAIGreen;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = LocalizedString(@"siwc_disconnect");
                cell.textLabel.textColor = [UIColor redColor];
            }
        } else {
            if (indexPath.row == 0) {
                cell.textLabel.text = LocalizedString(@"siwc_login_btn");
                cell.textLabel.textColor = openAIGreen;
                cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = LocalizedString(@"siwc_manual_btn");
                cell.textLabel.textColor = [UIColor darkGrayColor];
                cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
            }
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = LocalizedString(@"model_label");
            CGFloat cellW = cell.contentView.bounds.size.width > 0 ? cell.contentView.bounds.size.width : w;
            CGFloat labelW = 100.0;
            self.modelField.frame = CGRectMake(labelW, 8, cellW - labelW - 20, 28);
            self.modelField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:self.modelField];
        } else {
            if (self.isFetchingModels) {
                cell.textLabel.text = LocalizedString(@"fetching_models");
                cell.textLabel.textColor = [UIColor grayColor];
                UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                [spin startAnimating];
                cell.accessoryView = spin;
            } else {
                cell.textLabel.text = LocalizedString(@"fetch_models_btn");
                cell.textLabel.textColor = openAIGreen;
            }
        }
    } else if (indexPath.section == 3) {
        // Dinamik Model Ek Özellikleri & Araçlar (Reasoning Slider / Apple Toggle Switchler)
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        NSArray *rows = [self capabilityRowTypesForCurrentModel];
        NSString *rowType = (indexPath.row < rows.count) ? rows[indexPath.row] : @"";
        CGFloat cellW = cell.contentView.bounds.size.width > 0 ? cell.contentView.bounds.size.width : w;

        if ([rowType isEqualToString:@"reasoning_effort"]) {
            UILabel *titleLbl = [cell.contentView viewWithTag:9001];
            if (!titleLbl) {
                titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, cellW * 0.55, 22)];
                titleLbl.tag = 9001;
                titleLbl.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
                titleLbl.textColor = [UIColor blackColor];
                titleLbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
                [cell.contentView addSubview:titleLbl];
            }
            titleLbl.text = LocalizedString(@"cap_reasoning_effort");

            self.reasoningEffortValueLabel.frame = CGRectMake(cellW - 156, 8, 140, 22);
            self.reasoningEffortValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            [self updateReasoningEffortLabelText];
            [cell.contentView addSubview:self.reasoningEffortValueLabel];

            self.reasoningEffortSlider.frame = CGRectMake(16, 36, cellW - 32, 30);
            self.reasoningEffortSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:self.reasoningEffortSlider];
        } else if ([rowType isEqualToString:@"reasoning_summary"]) {
            cell.textLabel.text = LocalizedString(@"cap_reasoning_summary");
            cell.accessoryView = self.reasoningSummarySwitch;
        } else if ([rowType isEqualToString:@"temperature"]) {
            UILabel *titleLbl = [cell.contentView viewWithTag:9002];
            if (!titleLbl) {
                titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, cellW * 0.65, 22)];
                titleLbl.tag = 9002;
                titleLbl.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
                titleLbl.textColor = [UIColor blackColor];
                titleLbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
                [cell.contentView addSubview:titleLbl];
            }
            titleLbl.text = LocalizedString(@"cap_temperature");

            self.temperatureValueLabel.frame = CGRectMake(cellW - 96, 8, 80, 22);
            self.temperatureValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            [cell.contentView addSubview:self.temperatureValueLabel];

            self.temperatureSlider.frame = CGRectMake(16, 36, cellW - 32, 30);
            self.temperatureSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:self.temperatureSlider];
        } else if ([rowType isEqualToString:@"web_search"]) {
            cell.textLabel.text = LocalizedString(@"cap_web_search");
            self.webSearchSwitch.on = [OpenAIClient sharedClient].enableWebSearch;
            cell.accessoryView = self.webSearchSwitch;
        } else if ([rowType isEqualToString:@"code_interpreter"]) {
            cell.textLabel.text = LocalizedString(@"cap_code_interpreter");
            self.codeInterpreterSwitch.on = [OpenAIClient sharedClient].enableCodeInterpreter;
            cell.accessoryView = self.codeInterpreterSwitch;
        }
    } else if (indexPath.section == 4) {
        NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
        if (indexPath.row < (NSInteger)list.count) {
            NSMutableDictionary *item = list[indexPath.row];
            BOOL isEnabled = [item[@"enabled"] boolValue];

            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.textLabel.text = item[@"content"] ?: @"";
            cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
            cell.textLabel.numberOfLines = 0; // Bütün metni tam gösterir, kesilmez
            cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
            cell.textLabel.textColor = [UIColor blackColor];
            cell.detailTextLabel.text = nil;

            // Apple standart Checkmark / Tik işareti
            cell.accessoryType = isEnabled ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else {
            // "+ Yeni Talimat Ekle" satırı
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.textLabel.text = LocalizedString(@"add_prompt_button");
            cell.textLabel.textColor = openAIGreen;
            cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15.0];
            cell.textLabel.numberOfLines = 1;
            cell.detailTextLabel.text = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    } else if (indexPath.section == 5) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = LocalizedString(@"apikey_label");
        CGFloat cellW = cell.contentView.bounds.size.width > 0 ? cell.contentView.bounds.size.width : w;
        CGFloat labelW = 115.0;
        self.apiKeyField.frame = CGRectMake(labelW, 8, cellW - labelW - 20, 28);
        self.apiKeyField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:self.apiKeyField];
    } else if (indexPath.section == 6) {
        // İLERİ SEVİYE AYARLAR (Ayrı alt sayfaya giden Apple Navigation Row)
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.textLabel.text = LocalizedString(@"adv_menu_row");
        cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = LocalizedString(@"host_id_label");
            cell.detailTextLabel.text = [OpenAIClient sharedClient].hostId;
            cell.detailTextLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:11.0];
        } else {
            cell.textLabel.text = LocalizedString(@"version_label");
            cell.detailTextLabel.text = @"v1.7.1 (Pure iOS 8 UI)";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        [self.languagePickerField becomeFirstResponder];
    } else if (indexPath.section == 1) {
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            if (indexPath.row == 2) {
                [self manageUsageAction];
            } else if (indexPath.row == 3) {
                [self disconnectAccountAction];
            }
        } else {
            if (indexPath.row == 0) {
                [self signInWithChatGPTAction];
            } else if (indexPath.row == 1) {
                [self pasteManualCallbackAction];
            }
        }
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        if (!self.isFetchingModels) {
            [self refreshModelsAction];
        }
    } else if (indexPath.section == 4) {
        NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
        if (indexPath.row < (NSInteger)list.count) {
            // Yazının neresine tıklanırsa tıklansın tik durumunu değiştir
            NSMutableDictionary *item = list[indexPath.row];
            BOOL current = [item[@"enabled"] boolValue];
            item[@"enabled"] = @(!current);
            [[OpenAIClient sharedClient] saveSystemPromptsList:list];
            [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        } else {
            // Yeni Talimat Ekle
            [self addNewPromptAction];
        }
    } else if (indexPath.section == 6) {
        // İleri Seviye Ayarlar alt sayfasına Apple Push animasyonu ile geçiş yap
        AdvancedSettingsViewController *advVC = [[AdvancedSettingsViewController alloc] init];
        [self.navigationController pushViewController:advVC animated:YES];
    }
}

#pragma mark - Table View Editing (Swipe to Delete / Edit)

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 4) {
        NSInteger count = [OpenAIClient sharedClient].systemPromptsList.count;
        return (indexPath.row < count);
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 4 && editingStyle == UITableViewCellEditingStyleDelete) {
        NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
        if (indexPath.row < (NSInteger)list.count) {
            [list removeObjectAtIndex:indexPath.row];
            [[OpenAIClient sharedClient] saveSystemPromptsList:list];
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }
}

- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 4) {
        NSInteger count = [OpenAIClient sharedClient].systemPromptsList.count;
        if (indexPath.row < count) {
            // 1. Silme Aksiyonu (Türkçe/İngilizce "Sil" / "Delete")
            UITableViewRowAction *deleteAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
                                                                                    title:LocalizedString(@"delete_button")
                                                                                  handler:^(UITableViewRowAction *action, NSIndexPath *ip) {
                NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
                if (ip.row < (NSInteger)list.count) {
                    [list removeObjectAtIndex:ip.row];
                    [[OpenAIClient sharedClient] saveSystemPromptsList:list];
                    [tableView deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
                }
            }];

            // 2. Düzenle Aksiyonu (Mavi Apple Stili)
            UITableViewRowAction *editAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal
                                                                                  title:LocalizedString(@"edit_prompt_title")
                                                                                handler:^(UITableViewRowAction *action, NSIndexPath *ip) {
                [self editPromptAtIndex:ip.row];
            }];
            editAction.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1.0];

            return @[deleteAction, editAction];
        }
    }
    return nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
