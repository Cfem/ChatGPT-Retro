#import "SettingsViewController.h"
#import "OpenAIClient.h"
#import "LocalizationManager.h"
#import "ModelSelectionViewController.h"
#import "AccountLoginViewController.h"
#import "AdvancedSettingsViewController.h"
#import "SystemPromptDetailViewController.h"

@interface SettingsViewController () <ModelSelectionDelegate, AccountLoginDelegate, SystemPromptDetailDelegate, UIPickerViewDataSource, UIPickerViewDelegate>

@property (nonatomic, strong) UITextField *languagePickerField;
@property (nonatomic, strong) UIPickerView *languagePicker;

// Dynamic Model Capability Controls (Section 1)
@property (nonatomic, strong) UISlider *reasoningEffortSlider;
@property (nonatomic, strong) UILabel *reasoningEffortValueLabel;
@property (nonatomic, strong) UISwitch *reasoningSummarySwitch;
@property (nonatomic, strong) UISlider *temperatureSlider;
@property (nonatomic, strong) UILabel *temperatureValueLabel;
@property (nonatomic, strong) UISwitch *webSearchSwitch;
@property (nonatomic, strong) UISwitch *codeInterpreterSwitch;

@end

@implementation SettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = LocalizedString(@"settings_title");

    // Apple minimalist estetik: Sol ve sağ bar butonları kaldırıldı (karanlık alana basınca sessizce kaydeder ve kapatır)
    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.rightBarButtonItem = nil;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(languageDidChange:)
                                                 name:kLanguageDidChangeNotification
                                               object:nil];

    [self setupFields];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.webSearchSwitch.on = [OpenAIClient sharedClient].enableWebSearch;
    [self.tableView reloadData];
}

- (void)languageDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.title = LocalizedString(@"settings_title");
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

- (void)setupFields {
    UIColor *openAIGreen = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];

    // Language Picker Field & Accessory Toolbar (Gizli tetikleyici, tekerlek açılır)
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

    // Dynamic Model Capability Controls (Section 1)
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
}

#pragma mark - Capability Helpers

- (NSString *)activeModelString {
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

#pragma mark - Delegates & Silent Save

- (void)saveCurrentSettingsSilently {
    [self.view endEditing:YES];
    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }
}

- (void)modelSelectionDidSelectModel:(NSString *)model {
    [self.tableView reloadData];
    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }
}

- (void)accountLoginStateDidChange {
    [self.tableView reloadData];
    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }
}

- (void)systemPromptDidSaveOrDelete {
    [self.tableView reloadData];
    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }
}

#pragma mark - Language Picker

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

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1; // Model seçimi (Sağa giden sayfa)
    if (section == 1) return [self capabilityRowTypesForCurrentModel].count; // Model Özellikleri (Reasoning / Temp / Araçlar)
    if (section == 2) {
        // Özel Sistem Talimatları Listesi + "+ Yeni Talimat Ekle"
        return [OpenAIClient sharedClient].systemPromptsList.count + 1;
    }
    if (section == 3) return 1; // Giriş ve Hesap Ayarları (Sağa giden sayfa)
    if (section == 4) return 1; // İleri Seviye Maliyet ve Hafıza Ayarları (Sağa giden sayfa)
    if (section == 5) return 1; // Dil Seçeneği
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    // Kullanıcı isteği: "Bütün Ayarlardaki 'DİL SEÇENEĞİ' 'CHATGPT ile GİRİŞ YAP' gibi her satırdaki başlıkları da sil"
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2) {
        return LocalizedString(@"instructions_footer");
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        NSArray *rows = [self capabilityRowTypesForCurrentModel];
        if (indexPath.row < rows.count) {
            NSString *type = rows[indexPath.row];
            if ([type isEqualToString:@"reasoning_effort"] || [type isEqualToString:@"temperature"]) {
                return 74.0;
            }
        }
    }
    return 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *extraKey = @"";
    if (indexPath.section == 1) {
        NSArray *rows = [self capabilityRowTypesForCurrentModel];
        if (indexPath.row < rows.count) extraKey = rows[indexPath.row];
    }
    NSString *cellId = [NSString stringWithFormat:@"SettingCell_%ld_%ld_%@", (long)indexPath.section, (long)indexPath.row, extraKey];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        // Sistem Talimatı satırları için Value1 (Solda kalın başlık, sağda gri özet metin)
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
    cell.detailTextLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];

    for (UIView *sub in cell.contentView.subviews) {
        if (sub == self.reasoningEffortSlider || sub == self.reasoningEffortValueLabel ||
            sub == self.temperatureSlider || sub == self.temperatureValueLabel) {
            [sub removeFromSuperview];
        }
    }

    CGFloat w = tableView.bounds.size.width;
    UIColor *openAIGreen = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];

    if (indexPath.section == 0) {
        // SECTION 0: MODEL SEÇİMİ (Apple Navigation Row)
        cell.textLabel.text = LocalizedString(@"model_label");
        cell.detailTextLabel.text = [self activeModelString];
        cell.detailTextLabel.textColor = openAIGreen;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        // SECTION 1: MODEL EK ÖZELLİKLERİ VE ARAÇLAR
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
    } else if (indexPath.section == 2) {
        // SECTION 2: ÖZEL SİSTEM TALİMATLARI VE BELLEK
        // Kullanıcı isteği: "solda siyah başlık sağda yazı ... devam şeklinde her yerden tiklenebilir halde yapacağız"
        NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
        if (indexPath.row < (NSInteger)list.count) {
            NSDictionary *item = list[indexPath.row];
            BOOL isEnabled = [item[@"enabled"] boolValue];

            NSString *title = item[@"title"] ?: @"";
            NSString *content = item[@"content"] ?: @"";

            if (title.length == 0) {
                NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                NSString *firstLine = lines.firstObject ?: @"";
                title = (firstLine.length > 20) ? [firstLine substringToIndex:20] : (firstLine.length > 0 ? firstLine : @"Talimat");
            }

            // Tek satırda özetleme ("... devam şeklinde")
            NSString *cleanContent = [content stringByReplacingOccurrencesOfString:@"\n" withString:@" "];

            cell.textLabel.text = title;
            cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15.0];
            cell.textLabel.textColor = [UIColor blackColor];
            cell.textLabel.numberOfLines = 1;

            cell.detailTextLabel.text = cleanContent;
            cell.detailTextLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
            cell.detailTextLabel.textColor = [UIColor grayColor];
            cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;

            // Her yerden tiklenebilir (Apple checkmark)
            cell.accessoryType = isEnabled ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

            // Satırın en sağına detay/düzenleme sayfasına geçiş için Disclosure Button (i simgesi)
            UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
            infoButton.tag = 1000 + indexPath.row;
            [infoButton addTarget:self action:@selector(instructionInfoButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            cell.accessoryView = infoButton;
        } else {
            // "+ Yeni Talimat Ekle" satırı
            cell.textLabel.text = LocalizedString(@"add_prompt_button");
            cell.textLabel.textColor = openAIGreen;
            cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15.0];
            cell.textLabel.numberOfLines = 1;
            cell.detailTextLabel.text = nil;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.accessoryView = nil;
        }
    } else if (indexPath.section == 3) {
        // SECTION 3: HESAP VE GİRİŞ AYARLARI (Sağa giden Apple Navigation Row)
        cell.textLabel.text = LocalizedString(@"account_login_menu_row");
        cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            NSString *email = [OpenAIClient sharedClient].userEmail;
            cell.detailTextLabel.text = (email && email.length > 0) ? email : LocalizedString(@"siwc_connected");
            cell.detailTextLabel.textColor = openAIGreen;
        } else if ([OpenAIClient sharedClient].apiKey.length > 0) {
            cell.detailTextLabel.text = @"API Key";
            cell.detailTextLabel.textColor = openAIGreen;
        } else {
            cell.detailTextLabel.text = nil;
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 4) {
        // SECTION 4: İLERİ SEVİYE MALİYET VE HAFIZA AYARLARI (Sağa giden Apple Navigation Row)
        cell.textLabel.text = LocalizedString(@"adv_menu_row");
        cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 5) {
        // SECTION 5: DİL SEÇENEĞİ
        cell.textLabel.text = LocalizedString(@"language_label");
        cell.detailTextLabel.text = [[LocalizationManager sharedManager] displayNameForLanguage:[LocalizationManager sharedManager].selectedLanguage];
        cell.detailTextLabel.textColor = openAIGreen;
        cell.detailTextLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    return cell;
}

- (void)instructionInfoButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag - 1000;
    [self openInstructionDetailAtIndex:index];
}

- (void)openInstructionDetailAtIndex:(NSInteger)index {
    NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
    SystemPromptDetailViewController *detailVC = [[SystemPromptDetailViewController alloc] init];
    detailVC.delegate = self;

    if (index >= 0 && index < (NSInteger)list.count) {
        NSDictionary *item = list[index];
        detailVC.promptIndex = index;
        detailVC.promptId = item[@"id"];
        detailVC.initialTitle = item[@"title"];
        detailVC.initialContent = item[@"content"];
        detailVC.isEnabled = [item[@"enabled"] boolValue];
    } else {
        detailVC.promptIndex = -1;
        detailVC.initialTitle = @"";
        detailVC.initialContent = @"";
        detailVC.isEnabled = YES;
    }

    [self.navigationController pushViewController:detailVC animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        // Model Seçim sayfasına geçiş
        ModelSelectionViewController *modelVC = [[ModelSelectionViewController alloc] init];
        modelVC.delegate = self;
        [self.navigationController pushViewController:modelVC animated:YES];
    } else if (indexPath.section == 2) {
        NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
        if (indexPath.row < (NSInteger)list.count) {
            // Kullanıcı isteği: Satırın neresine tıklanırsa tıklansın tikle / tiki kaldır
            NSMutableDictionary *item = list[indexPath.row];
            BOOL current = [item[@"enabled"] boolValue];
            item[@"enabled"] = @(!current);
            [[OpenAIClient sharedClient] saveSystemPromptsList:list];
            [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                [self.delegate settingsDidUpdate];
            }
        } else {
            // "+ Yeni Talimat Ekle" satırına tıklandığında sağa giden yeni talimat sayfasına git
            [self openInstructionDetailAtIndex:-1];
        }
    } else if (indexPath.section == 3) {
        // Hesap ve Giriş Ayarları sayfasına geçiş
        AccountLoginViewController *accVC = [[AccountLoginViewController alloc] init];
        accVC.delegate = self;
        [self.navigationController pushViewController:accVC animated:YES];
    } else if (indexPath.section == 4) {
        // İleri Seviye Ayarlar sayfasına geçiş
        AdvancedSettingsViewController *advVC = [[AdvancedSettingsViewController alloc] init];
        [self.navigationController pushViewController:advVC animated:YES];
    } else if (indexPath.section == 5) {
        // Dil seçimi picker'ını aç
        [self.languagePickerField becomeFirstResponder];
    }
}

#pragma mark - Table View Swipe to Delete

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) {
        NSInteger count = [OpenAIClient sharedClient].systemPromptsList.count;
        return (indexPath.row < count);
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2 && editingStyle == UITableViewCellEditingStyleDelete) {
        NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
        if (indexPath.row < (NSInteger)list.count) {
            [list removeObjectAtIndex:indexPath.row];
            [[OpenAIClient sharedClient] saveSystemPromptsList:list];
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                [self.delegate settingsDidUpdate];
            }
        }
    }
}

- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) {
        NSInteger count = [OpenAIClient sharedClient].systemPromptsList.count;
        if (indexPath.row < count) {
            // Kullanıcı isteği: "düzenle yazısı kaldırılcak ve sağ tarafta sadece kırmızı sil olucak"
            UITableViewRowAction *deleteAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
                                                                                    title:LocalizedString(@"delete_button")
                                                                                  handler:^(UITableViewRowAction *action, NSIndexPath *ip) {
                NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
                if (ip.row < (NSInteger)list.count) {
                    [list removeObjectAtIndex:ip.row];
                    [[OpenAIClient sharedClient] saveSystemPromptsList:list];
                    [tableView deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
                    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                        [self.delegate settingsDidUpdate];
                    }
                }
            }];
            return @[deleteAction];
        }
    }
    return nil;
}

@end
