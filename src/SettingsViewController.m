#import "SettingsViewController.h"
#import "GeminiClient.h"
#import "QRScannerViewController.h"

@interface SettingsViewController () <QRScannerDelegate>

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
    _apiKeyField.placeholder = @"AIzaSy... (Buraya yapıştırın veya kamerayla tarayın)";
    _apiKeyField.text = [GeminiClient sharedClient].apiKey;
    _apiKeyField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _apiKeyField.secureTextEntry = YES;
    _apiKeyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _apiKeyField.autocorrectionType = UITextAutocorrectionTypeNo;
    _apiKeyField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // 2. Model
    _modelField = [[UITextField alloc] initWithFrame:CGRectZero];
    _modelField.placeholder = @"gemini-1.5-flash";
    _modelField.text = [GeminiClient sharedClient].selectedModel;
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
    NSString *model = self.modelField.text ?: @"gemini-1.5-flash";

    [[GeminiClient sharedClient] saveApiKey:key];
    [[GeminiClient sharedClient] saveSelectedModel:model];

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

- (void)scanApiKeyQRAction {
    [self.view endEditing:YES];
    QRScannerViewController *scanner = [[QRScannerViewController alloc] init];
    scanner.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:scanner];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)refreshModelsAction {
    [self.view endEditing:YES];

    NSString *currentKey = self.apiKeyField.text ?: @"";
    [[GeminiClient sharedClient] saveApiKey:currentKey];

    if (![[GeminiClient sharedClient] isAuthenticated]) {
        [self showAlertWithTitle:@"API Anahtarı Gerekli" 
                         message:@"Modelleri çekebilmek için lütfen önce yukarıdaki kutuya geçerli bir Gemini API Anahtarı girin veya QR kod ile okutun."];
        return;
    }

    self.isFetchingModels = YES;
    [self.tableView reloadData];

    [[GeminiClient sharedClient] fetchAvailableModelsWithCompletion:^(NSArray *models, NSError *error) {
        self.isFetchingModels = NO;
        if (error) {
            [self showAlertWithTitle:@"Hata" message:error.localizedDescription];
            [self.tableView reloadData];
            return;
        }

        if (models.count == 0) {
            [self showAlertWithTitle:@"Model Bulunamadı" message:@"Erişilebilir model listesi boş döndü."];
            [self.tableView reloadData];
            return;
        }

        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Model Seçin"
                                                                        message:@"Kullanmak istediğiniz Gemini modeline dokunun:"
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSString *m in models) {
            [picker addAction:[UIAlertAction actionWithTitle:m style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                self.modelField.text = m;
                [[GeminiClient sharedClient] saveSelectedModel:m];
                if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                    [self.delegate settingsDidUpdate];
                }
                [self.tableView reloadData];
            }]];
        }
        [picker addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
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

#pragma mark - QRScannerDelegate

- (void)qrScannerDidScanCode:(NSString *)code {
    NSString *trimmed = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.apiKeyField.text = trimmed;
    [[GeminiClient sharedClient] saveApiKey:trimmed];
    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }
    [self showAlertWithTitle:@"API Anahtarı Okundu"
                     message:@"API Anahtarınız QR koddan başarıyla alındı ve kaydedildi!"];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2; // API Key TextField, [Kamerayla QR Koddan API Key Oku]
    if (section == 1) return 2; // Model TextField, [Modelleri Canlı Güncelle]
    if (section == 2) return 1; // [Ayarları Kaydet ve Uygula]
    return 2; // Sistem bilgisi
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"GOOGLE AI STUDIO API ANAHTARI";
    if (section == 1) return @"GEMINI MODELİ";
    if (section == 2) return @"KAYDET";
    return @"SİSTEM BİLGİSİ";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"aistudio.google.com/apikey adresinden ücretsiz alacağınız API anahtarını buraya yapıştırabilir veya bilgisayar/telefon ekranınızdan QR kod olarak okutabilirsiniz.";
    if (section == 1) return @"Yüksek günlük ücretsiz kota (1.500 mesaj/gün) için 'gemini-1.5-flash' veya 'gemini-2.0-flash' modellerini tercih edin.";
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
        if (indexPath.row == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"API Key";
            self.apiKeyField.frame = CGRectMake(110, 8, w - 126, 28);
            [cell.contentView addSubview:self.apiKeyField];
        } else {
            cell.textLabel.text = @"📷 Kamerayla QR Koddan API Anahtarı Oku";
            cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
        }
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
                cell.textLabel.text = @"🔄 Modelleri Canlı Güncelle (Refresh Models)";
                cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
            }
        }
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"📥 Ayarları Kaydet ve Uygula";
        cell.textLabel.textColor = [UIColor colorWithRed:0.1 green:0.6 blue:0.1 alpha:1.0];
        cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Hedef Cihaz";
            cell.detailTextLabel.text = @"iPad Mini 1 (iOS 8.4)";
        } else {
            cell.textLabel.text = @"Sürüm";
            cell.detailTextLabel.text = @"v2.6 (Pure API Key Edition)";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0 && indexPath.row == 1) {
        [self scanApiKeyQRAction];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        if (!self.isFetchingModels) {
            [self refreshModelsAction];
        }
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        [self saveSettingsAction];
    }
}

@end
