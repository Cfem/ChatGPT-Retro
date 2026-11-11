#import "SettingsViewController.h"
#import "GeminiClient.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UITextField *apiKeyTextField;
@property (nonatomic, strong) NSMutableArray *models;
@property (nonatomic, assign) NSInteger selectedModelIndex;
@property (nonatomic, assign) BOOL isFetchingModels;
@property (nonatomic, strong) UIActivityIndicatorView *fetchSpinner;
@end

@implementation SettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _models = [NSMutableArray array];
        NSArray *cached = [GeminiClient sharedClient].cachedModels;
        if (cached && cached.count > 0) {
            [_models addObjectsFromArray:cached];
        } else {
            // İlk açılışta temel varsayılanlar
            [_models addObjectsFromArray:@[@"gemini-1.5-flash", @"gemini-1.5-flash-8b", @"gemini-1.5-pro"]];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ayarlar";

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

- (void)refreshModelsTapped {
    [self.view endEditing:YES];
    NSString *currentKey = self.apiKeyTextField.text;
    if (currentKey.length > 5) {
        [[GeminiClient sharedClient] saveApiKey:currentKey];
    }

    if (![[GeminiClient sharedClient] hasApiKey]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"API Key Gerekli" 
                                                                       message:@"Modelleri çekebilmek için lütfen önce geçerli bir API Key girin." 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    self.isFetchingModels = YES;
    [self.tableView reloadData];

    [[GeminiClient sharedClient] fetchAvailableModelsWithCompletion:^(NSArray *newModels, NSError *error) {
        self.isFetchingModels = NO;
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Model Listesi Alınamadı" 
                                                                           message:error.localizedDescription 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            [self.tableView reloadData];
            return;
        }

        if (newModels.count > 0) {
            [self.models removeAllObjects];
            [self.models addObjectsFromArray:newModels];
            self.selectedModelIndex = 0;
            [[GeminiClient sharedClient] saveSelectedModel:self.models[0]];
        }
        [self.tableView reloadData];
    }];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1; // API Key
    if (section == 1) return self.models.count + 1; // Modeller + "Refresh Models" Butonu
    return 2; // Cihaz & iOS bilgisi
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"GOOGLE AI STUDIO API ANAHTARI";
    if (section == 1) return @"GEMINI MODELLERİ (CANLI LİSTE)";
    if (section == 2) return @"SİSTEM BİLGİSİ";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Ücretsiz API anahtarınızı aistudio.google.com adresinden alabilirsiniz.";
    }
    if (section == 1) {
        return @"'Modelleri Yenile' butonuna basarak Google API'nizdeki güncel modelleri canlı olarak listeleyebilirsiniz.";
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
        if (indexPath.row == self.models.count) {
            // "Modelleri Yenile" Buton Satırı
            if (self.isFetchingModels) {
                cell.textLabel.text = @"Modeller alınıyor...";
                cell.textLabel.textColor = [UIColor grayColor];
                UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                [spinner startAnimating];
                cell.accessoryView = spinner;
            } else {
                cell.textLabel.text = @"🔄 Modelleri Yenile (Refresh Models)";
                cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
                cell.accessoryView = nil;
            }
        } else {
            cell.accessoryView = nil;
            cell.textLabel.text = self.models[indexPath.row];
            if (indexPath.row == self.selectedModelIndex) {
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
        }
    } else if (indexPath.section == 2) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Hedef Cihaz";
            cell.detailTextLabel.text = @"iPad Mini 1 (iOS 8.4)";
        } else {
            cell.textLabel.text = @"İşlemci / RAM";
            cell.detailTextLabel.text = @"Apple A5 / 512 MB";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (indexPath.row == self.models.count) {
            if (!self.isFetchingModels) {
                [self refreshModelsTapped];
            }
        } else {
            self.selectedModelIndex = indexPath.row;
            [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

@end
