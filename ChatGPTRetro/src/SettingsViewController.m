#import "SettingsViewController.h"
#import "OpenAIClient.h"

@interface SettingsViewController ()

@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, assign) BOOL isFetchingModels;

@end

@implementation SettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
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
                                                                             action:@selector(saveSettingsAction)];

    [self setupFields];
}

- (void)setupFields {
    // 1. API Key
    _apiKeyField = [[UITextField alloc] initWithFrame:CGRectZero];
    _apiKeyField.placeholder = @"sk-... (OpenAI API Anahtarı)";
    _apiKeyField.text = [OpenAIClient sharedClient].apiKey;
    _apiKeyField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _apiKeyField.secureTextEntry = YES;
    _apiKeyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _apiKeyField.autocorrectionType = UITextAutocorrectionTypeNo;
    _apiKeyField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // 2. Model
    _modelField = [[UITextField alloc] initWithFrame:CGRectZero];
    _modelField.placeholder = @"gpt-4o-mini";
    _modelField.text = [OpenAIClient sharedClient].selectedModel;
    _modelField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _modelField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _modelField.autocorrectionType = UITextAutocorrectionTypeNo;
    _modelField.clearButtonMode = UITextFieldViewModeWhileEditing;
}

- (void)closeButtonTapped {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Actions

- (void)saveSettingsAction {
    [self.view endEditing:YES];

    NSString *key = self.apiKeyField.text ?: @"";
    NSString *model = self.modelField.text ?: @"gpt-4o-mini";

    [[OpenAIClient sharedClient] saveApiKey:key];
    [[OpenAIClient sharedClient] saveSelectedModel:model];

    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }

    NSString *msg = [NSString stringWithFormat:@"Ayarlar başarıyla kaydedildi!\n\n• API Anahtarı: %lu karakter\n• Seçili Model: %@",
                     (unsigned long)key.length, model];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Kaydedildi" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshModelsAction {
    [self.view endEditing:YES];

    NSString *currentKey = self.apiKeyField.text ?: @"";
    [[OpenAIClient sharedClient] saveApiKey:currentKey];

    if (![[OpenAIClient sharedClient] isAuthenticated]) {
        [self showAlertWithTitle:@"API Anahtarı Gerekli" 
                         message:@"Modelleri çekebilmek için lütfen geçerli bir OpenAI API Anahtarı (sk-...) girin."];
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
            [self showAlertWithTitle:@"Model Bulunamadı" message:@"OpenAI model listesi boş döndü."];
            [self.tableView reloadData];
            return;
        }

        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Model Seçin"
                                                                        message:@"Kullanmak istediğiniz OpenAI modelini seçin:"
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];

        for (NSString *m in models) {
            [picker addAction:[UIAlertAction actionWithTitle:m style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                self.modelField.text = m;
                [[OpenAIClient sharedClient] saveSelectedModel:m];
                if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                    [self.delegate settingsDidUpdate];
                }
            }]];
        }

        [picker addAction:[UIAlertAction actionWithTitle:@"İptal" style:UIAlertActionStyleCancel handler:nil]];
        picker.popoverPresentationController.sourceView = self.view;
        picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, 200, 1, 1);
        [self presentViewController:picker animated:YES completion:nil];
        [self.tableView reloadData];
    }];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 2;
    if (section == 2) return 1;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"OPENAI API ANAHTARI";
    if (section == 1) return @"CHATGPT MODELİ";
    if (section == 2) return @"KAYDET";
    return @"SİSTEM BİLGİSİ";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"platform.openai.com/api-keys adresinden alacağınız API anahtarını (sk-...) buraya yapıştırabilirsiniz.";
    if (section == 1) return @"Hızlı ve ekonomik yanıtlar için 'gpt-4o-mini' tavsiye edilir.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"Cell_%ld_%ld", (long)indexPath.section, (long)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.textColor = [UIColor blackColor];
    cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
    cell.detailTextLabel.text = nil;

    CGFloat w = tableView.bounds.size.width;

    if (indexPath.section == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"API Key";
        self.apiKeyField.frame = CGRectMake(110, 8, w - 126, 28);
        [cell.contentView addSubview:self.apiKeyField];
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Model";
            self.modelField.frame = CGRectMake(110, 8, w - 126, 28);
            [cell.contentView addSubview:self.modelField];
        } else {
            if (self.isFetchingModels) {
                cell.textLabel.text = @"Modeller taranıyor...";
                cell.textLabel.textColor = [UIColor grayColor];
                UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                [spin startAnimating];
                cell.accessoryView = spin;
            } else {
                cell.textLabel.text = @"🔄 Modelleri Canlı Güncelle (Fetch Models)";
                cell.textLabel.textColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
            }
        }
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"📥 Ayarları Kaydet ve Uygula";
        cell.textLabel.textColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
        cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Hedef Cihaz";
            cell.detailTextLabel.text = @"iPad Mini 1 (iOS 8.4)";
        } else {
            cell.textLabel.text = @"Sürüm";
            cell.detailTextLabel.text = @"v1.0 (ChatGPT Retro Edition)";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1 && indexPath.row == 1) {
        if (!self.isFetchingModels) {
            [self refreshModelsAction];
        }
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        [self saveSettingsAction];
    }
}

@end
