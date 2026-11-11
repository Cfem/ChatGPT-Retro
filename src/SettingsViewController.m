#import "SettingsViewController.h"
#import "GeminiClient.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UITextField *apiKeyTextField;
@property (nonatomic, strong) NSArray *models;
@property (nonatomic, strong) NSArray *modelTitles;
@property (nonatomic, assign) NSInteger selectedModelIndex;
@end

@implementation SettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _models = @[@"gemini-1.5-flash", @"gemini-1.5-flash-8b", @"gemini-1.5-pro"];
        _modelTitles = @[@"Gemini 1.5 Flash (Hızlı / Önerilen)",
                         @"Gemini 1.5 Flash-8B (Ultra Hafif)",
                         @"Gemini 1.5 Pro (Gelişmiş Zeka)"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ayarlar";

    // iOS 8 Navigation Bar Stili
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Kapat"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(closeButtonTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Kaydet"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(saveButtonTapped)];

    NSString *currentModel = [GeminiClient sharedClient].selectedModel;
    NSUInteger idx = [self.models indexOfObject:currentModel];
    self.selectedModelIndex = (idx != NSNotFound) ? idx : 0;
}

- (void)closeButtonTapped {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveButtonTapped {
    [self.view endEditing:YES];
    
    NSString *key = self.apiKeyTextField.text;
    [[GeminiClient sharedClient] saveApiKey:key];
    
    if (self.selectedModelIndex < self.models.count) {
        [[GeminiClient sharedClient] saveSelectedModel:self.models[self.selectedModelIndex]];
    }

    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1; // API Key
    if (section == 1) return self.models.count; // Modeller
    return 2; // Cihaz & Model bilgisi
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"GOOGLE AI STUDIO API ANAHTARI";
    if (section == 1) return @"GEMINI MODELİ";
    if (section == 2) return @"SİSTEM BİLGİSİ";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Ücretsiz API anahtarınızı aistudio.google.com adresinden alabilirsiniz. API anahtarı iPad üzerinde yerel olarak saklanır.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"SettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellId];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor = [UIColor blackColor];
    cell.detailTextLabel.text = nil;

    if (indexPath.section == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (!self.apiKeyTextField) {
            self.apiKeyTextField = [[UITextField alloc] initWithFrame:CGRectMake(16, 8, cell.contentView.bounds.size.width - 32, 28)];
            self.apiKeyTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            self.apiKeyTextField.placeholder = @"AIzaSy...";
            self.apiKeyTextField.secureTextEntry = YES;
            self.apiKeyTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
            self.apiKeyTextField.text = [GeminiClient sharedClient].apiKey;
            self.apiKeyTextField.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
            self.apiKeyTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            self.apiKeyTextField.autocorrectionType = UITextAutocorrectionTypeNo;
        }
        [cell.contentView addSubview:self.apiKeyTextField];
        cell.textLabel.text = @"";
    } else if (indexPath.section == 1) {
        cell.textLabel.text = self.modelTitles[indexPath.row];
        if (indexPath.row == self.selectedModelIndex) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }
    } else if (indexPath.section == 2) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Hedef Cihaz";
            cell.detailTextLabel.text = @"iPad Mini 1 (iOS 8.4)";
        } else {
            cell.textLabel.text = @"Mimari & Bellek";
            cell.detailTextLabel.text = @"Apple A5 (armv7) / 512 MB";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        self.selectedModelIndex = indexPath.row;
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }
}

@end
