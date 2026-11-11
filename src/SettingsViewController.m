#import "SettingsViewController.h"
#import "GeminiClient.h"

@interface SettingsViewController ()

@property (nonatomic, strong) UITextField *clientIdField;
@property (nonatomic, strong) UITextField *clientSecretField;
@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UITextField *modelField;

@property (nonatomic, strong) UIAlertController *deviceAuthAlert;
@property (nonatomic, assign) BOOL isFetchingModels;

@end

@implementation SettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ayarlar & İşlemler";

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
    // 1. Client ID
    _clientIdField = [[UITextField alloc] initWithFrame:CGRectZero];
    _clientIdField.placeholder = @"Örn: 678744244381-...apps.googleusercontent.com";
    _clientIdField.text = [GeminiClient sharedClient].oauthClientId;
    _clientIdField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _clientIdField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _clientIdField.autocorrectionType = UITextAutocorrectionTypeNo;
    _clientIdField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // 2. Client Secret
    _clientSecretField = [[UITextField alloc] initWithFrame:CGRectZero];
    _clientSecretField.placeholder = @"Örn: GOCSPX-...";
    _clientSecretField.text = [GeminiClient sharedClient].oauthClientSecret;
    _clientSecretField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _clientSecretField.secureTextEntry = YES;
    _clientSecretField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _clientSecretField.autocorrectionType = UITextAutocorrectionTypeNo;
    _clientSecretField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // 3. API Key
    _apiKeyField = [[UITextField alloc] initWithFrame:CGRectZero];
    _apiKeyField.placeholder = @"AIzaSy...";
    _apiKeyField.text = [GeminiClient sharedClient].apiKey;
    _apiKeyField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _apiKeyField.secureTextEntry = YES;
    _apiKeyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _apiKeyField.autocorrectionType = UITextAutocorrectionTypeNo;
    _apiKeyField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // 4. Model
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

#pragma mark - BUTON 1: Ayarları Kaydet ve Uygula

- (void)saveSettingsAction {
    [self.view endEditing:YES];

    NSString *cid = self.clientIdField.text ?: @"";
    NSString *csec = self.clientSecretField.text ?: @"";
    NSString *key = self.apiKeyField.text ?: @"";
    NSString *model = self.modelField.text ?: @"gemini-1.5-flash";

    [[GeminiClient sharedClient] saveOAuthClientId:cid secret:csec];
    [[GeminiClient sharedClient] saveApiKey:key];
    [[GeminiClient sharedClient] saveSelectedModel:model];

    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }

    NSString *msg = [NSString stringWithFormat:@"Ayarlar başarıyla kaydedildi!\n\n• Client ID: %lu karakter\n• Client Secret: %lu karakter\n• API Key: %lu karakter\n• Model: %@",
                     (unsigned long)cid.length, (unsigned long)csec.length, (unsigned long)key.length, model];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Kaydedildi" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - BUTON 2: Google ile Giriş Yap (OAuth)

- (void)startGoogleOAuthFlow {
    [self.view endEditing:YES];

    NSString *cid = self.clientIdField.text ?: @"";
    NSString *csec = self.clientSecretField.text ?: @"";
    [[GeminiClient sharedClient] saveOAuthClientId:cid secret:csec];

    if (![[GeminiClient sharedClient] hasOAuthCredentials]) {
        [self showAlertWithTitle:@"Client ID / Secret Gerekli" 
                         message:@"Lütfen yukarıdaki Client ID ve Client Secret alanlarını doldurunuz."];
        return;
    }

    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Google Bağlantısı"
                                                                     message:@"Cihaz kodu alınıyor, lütfen bekleyin..."
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];

    [[GeminiClient sharedClient] startDeviceAuthFlowWithCompletion:^(NSString *userCode, NSString *verificationUrl, NSString *deviceCode, NSError *error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error) {
                [self showAlertWithTitle:@"Bağlantı Hatası" message:error.localizedDescription];
                return;
            }

            NSString *msg = [NSString stringWithFormat:@"Telefonunuzdan veya bilgisayarınızdan şu adrese gidin:\n\n%@\n\nVe bu kodu girip onaylayın:\n👉 %@ 👈\n\nOnayladıktan sonra bu ekran otomatik kapanacaktır.",
                             verificationUrl, userCode];

            self.deviceAuthAlert = [UIAlertController alertControllerWithTitle:@"Google Hesabınızı Onaylayın"
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [self.deviceAuthAlert addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:self.deviceAuthAlert animated:YES completion:nil];

            [[GeminiClient sharedClient] pollDeviceTokenWithDeviceCode:deviceCode interval:5 completion:^(BOOL success, NSError *pollErr) {
                [self.deviceAuthAlert dismissViewControllerAnimated:YES completion:^{
                    if (success) {
                        if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                            [self.delegate settingsDidUpdate];
                        }
                        [self.tableView reloadData];
                        [self showAlertWithTitle:@"Giriş Başarılı!" 
                                         message:@"Google hesabınız başarıyla bağlandı. Artık doğrudan hesabınızla kotasız konuşabilirsiniz."];
                    } else if (pollErr) {
                        [self showAlertWithTitle:@"Giriş Tamamlanamadı" message:pollErr.localizedDescription];
                    }
                }];
            }];
        }];
    }];
}

#pragma mark - BUTON 3: Modelleri Canlı Güncelle (Refresh Models)

- (void)refreshModelsAction {
    [self.view endEditing:YES];

    if (![[GeminiClient sharedClient] isAuthenticated]) {
        [self showAlertWithTitle:@"Giriş Gerekli" 
                         message:@"Modelleri çekebilmek için lütfen geçerli bir API Key girin veya Google Hesabınızı bağlayın."];
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

- (void)signOutAction {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Çıkış Yap"
                                                                   message:@"Google hesabınızdan çıkış yapmak istediğinize emin misiniz?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Çıkış Yap" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[GeminiClient sharedClient] signOutGoogleAccount];
        if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
            [self.delegate settingsDidUpdate];
        }
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [GeminiClient sharedClient].isGoogleAccountLinked ? 6 : 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3; // Client ID, Client Secret, [BUTON 2: Google ile Giriş Yap]
    if (section == 1) return 1; // [BUTON 1: Ayarları Kaydet ve Uygula]
    if (section == 2) return 2; // Model TextField, [BUTON 3: Modelleri Canlı Güncelle]
    if (section == 3) return 1; // API Key TextField
    if (section == 4) {
        if ([GeminiClient sharedClient].isGoogleAccountLinked) {
            return 2; // Bağlı hesap bilgisi, Çıkış Yap
        } else {
            return 2; // Sistem bilgisi (iPad Mini 1, v2.3)
        }
    }
    return 2; // Sistem bilgisi
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"GOOGLE OAUTH 2.0 (HESAP GİRİŞİ)";
    if (section == 1) return @"AYARLARI UYGULA";
    if (section == 2) return @"GEMINI MODELİ";
    if (section == 3) return @"GOOGLE AI STUDIO API ANAHTARI";
    if (section == 4 && [GeminiClient sharedClient].isGoogleAccountLinked) return @"BAĞLI GOOGLE HESABI";
    return @"SİSTEM BİLGİSİ";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Google Cloud Console'dan aldığınız TV/Device Client ID ve Secret'ı girip aşağıdaki butona basabilirsiniz.";
    if (section == 3) return @"OAuth yerine doğrudan API anahtarıyla kullanmak isterseniz anahtarınızı buraya yazabilirsiniz.";
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
    cell.detailTextLabel.text = nil;

    CGFloat w = tableView.bounds.size.width;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Client ID";
            self.clientIdField.frame = CGRectMake(110, 8, w - 126, 28);
            [cell.contentView addSubview:self.clientIdField];
        } else if (indexPath.row == 1) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Secret";
            self.clientSecretField.frame = CGRectMake(110, 8, w - 126, 28);
            [cell.contentView addSubview:self.clientSecretField];
        } else {
            // BUTON 2: Google ile Giriş Yap (OAuth)
            cell.textLabel.text = @"🔑 Google ile Giriş Yap (google.com/device)";
            cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
        }
    } else if (indexPath.section == 1) {
        // BUTON 1: Ayarları Kaydet ve Uygula
        cell.textLabel.text = @"📥 Ayarları Kaydet ve Uygula";
        cell.textLabel.textColor = [UIColor colorWithRed:0.1 green:0.6 blue:0.1 alpha:1.0];
        cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Model";
            self.modelField.frame = CGRectMake(110, 8, w - 126, 28);
            [cell.contentView addSubview:self.modelField];
        } else {
            // BUTON 3: Modelleri Canlı Güncelle
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
    } else if (indexPath.section == 3) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"API Key";
        self.apiKeyField.frame = CGRectMake(110, 8, w - 126, 28);
        [cell.contentView addSubview:self.apiKeyField];
    } else if (indexPath.section == 4 && [GeminiClient sharedClient].isGoogleAccountLinked) {
        if (indexPath.row == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"E-Posta";
            cell.detailTextLabel.text = [GeminiClient sharedClient].userEmail.length > 0 ? [GeminiClient sharedClient].userEmail : @"Giriş Yapıldı (Aktif)";
        } else {
            cell.textLabel.text = @"🔴 Hesaptan Çıkış Yap";
            cell.textLabel.textColor = [UIColor redColor];
        }
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Hedef Cihaz";
            cell.detailTextLabel.text = @"iPad Mini 1 (iOS 8.4)";
        } else {
            cell.textLabel.text = @"Sürüm";
            cell.detailTextLabel.text = @"v2.3 (FormSheet UI)";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0 && indexPath.row == 2) {
        // Buton 2: Google ile Giriş Yap
        [self startGoogleOAuthFlow];
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        // Buton 1: Ayarları Kaydet ve Uygula
        [self saveSettingsAction];
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        // Buton 3: Modelleri Canlı Güncelle
        if (!self.isFetchingModels) {
            [self refreshModelsAction];
        }
    } else if (indexPath.section == 4 && [GeminiClient sharedClient].isGoogleAccountLinked && indexPath.row == 1) {
        // Çıkış Yap
        [self signOutAction];
    }
}

@end
