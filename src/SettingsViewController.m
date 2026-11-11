#import "SettingsViewController.h"
#import "GeminiClient.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UISegmentedControl *authModeSegment;
@property (nonatomic, strong) UITextField *apiKeyTextField;
@property (nonatomic, strong) NSMutableArray *models;
@property (nonatomic, assign) NSInteger selectedModelIndex;
@property (nonatomic, assign) BOOL isFetchingModels;
@property (nonatomic, strong) UIAlertController *deviceAuthAlert;
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
    
    [[GeminiClient sharedClient] saveAuthMode:(GeminiAuthMode)self.authModeSegment.selectedSegmentIndex];

    if (self.apiKeyTextField.text) {
        [[GeminiClient sharedClient] saveApiKey:self.apiKeyTextField.text];
    }
    
    if (self.selectedModelIndex < self.models.count) {
        [[GeminiClient sharedClient] saveSelectedModel:self.models[self.selectedModelIndex]];
    }

    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)authModeChanged:(UISegmentedControl *)sender {
    [[GeminiClient sharedClient] saveAuthMode:(GeminiAuthMode)sender.selectedSegmentIndex];
    [self.tableView reloadData];
}

- (void)startGoogleLogin {
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Google Bağlantısı"
                                                                     message:@"Cihaz kodu alınıyor, lütfen bekleyin..."
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];

    [[GeminiClient sharedClient] startDeviceAuthFlowWithCompletion:^(NSString *userCode, NSString *verificationUrl, NSString *deviceCode, NSError *error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error) {
                UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Bağlantı Hatası"
                                                                                  message:error.localizedDescription
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                [errAlert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errAlert animated:YES completion:nil];
                return;
            }

            // Kullanıcıya onay kodunu göster
            NSString *msg = [NSString stringWithFormat:@"Telefonunuzdan veya bilgisayarınızdan şu adresi açın:\n\n%@\n\nVe bu kodu girin:\n👉 %@ 👈\n\nOnayladıktan sonra bu ekran otomatik güncellenecektir.",
                             verificationUrl, userCode];

            self.deviceAuthAlert = [UIAlertController alertControllerWithTitle:@"Google Hesabınızı Onaylayın"
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [self.deviceAuthAlert addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:self.deviceAuthAlert animated:YES completion:nil];

            // Arka planda sorgulamayı başlat
            [[GeminiClient sharedClient] pollDeviceTokenWithDeviceCode:deviceCode interval:5 completion:^(BOOL success, NSError *pollErr) {
                [self.deviceAuthAlert dismissViewControllerAnimated:YES completion:^{
                    if (success) {
                        UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"Giriş Başarılı!"
                                                                                    message:@"Google hesabınız başarıyla bağlandı. Artık doğrudan hesabınızla sohbet edebilirsiniz."
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                        [ok addAction:[UIAlertAction actionWithTitle:@"Harika" style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:ok animated:YES completion:nil];
                    } else if (pollErr) {
                        UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"Giriş Tamamlanamadı"
                                                                                      message:pollErr.localizedDescription
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                        [fail addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:fail animated:YES completion:nil];
                    }
                    [self.tableView reloadData];
                }];
            }];
        }];
    }];
}

- (void)signOutGoogle {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Çıkış Yap"
                                                                   message:@"Google hesabınızdan çıkış yapmak istediğinize emin misiniz?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Çıkış Yap" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[GeminiClient sharedClient] signOutGoogleAccount];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshModelsTapped {
    [self.view endEditing:YES];
    if (![[GeminiClient sharedClient] isAuthenticated]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Giriş Gerekli" 
                                                                       message:@"Modelleri çekebilmek için lütfen geçerli bir API Key girin veya Google hesabınızla giriş yapın." 
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
    return 4; // 0: Auth Mode, 1: Kimlik Detayı (Key/OAuth), 2: Modeller, 3: Sistem Bilgisi
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1; // Segment
    if (section == 1) {
        if (self.authModeSegment.selectedSegmentIndex == GeminiAuthModeOAuth) {
            return [[GeminiClient sharedClient] isAuthenticated] ? 2 : 1; // Durum + Çıkış Yap VEYA Giriş Yap
        }
        return 1; // API Key TextField
    }
    if (section == 2) return self.models.count + 1; // Modeller + Yenile Butonu
    return 2; // Cihaz bilgisi
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"KİMLİK DOĞRULAMA YÖNTEMİ";
    if (section == 1) {
        return (self.authModeSegment.selectedSegmentIndex == GeminiAuthModeOAuth) ? @"GOOGLE HESABI (OAUTH 2.0)" : @"GOOGLE AI STUDIO API ANAHTARI";
    }
    if (section == 2) return @"GEMINI MODELLERİ (CANLI LİSTE)";
    if (section == 3) return @"SİSTEM BİLGİSİ";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        if (self.authModeSegment.selectedSegmentIndex == GeminiAuthModeOAuth) {
            return @"Google OAuth Device Flow ile bilgisayarınızdan veya telefonunuzdan google.com/device adresinde onaylayarak kolayca giriş yapabilirsiniz.";
        }
        return @"Ücretsiz API anahtarınızı aistudio.google.com adresinden alabilirsiniz.";
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
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor = [UIColor blackColor];
    cell.detailTextLabel.text = nil;

    if (indexPath.section == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (!self.authModeSegment) {
            self.authModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"API Anahtarı", @"Google Hesabı"]];
            self.authModeSegment.frame = CGRectMake(16, 7, cell.contentView.bounds.size.width - 32, 30);
            self.authModeSegment.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            self.authModeSegment.selectedSegmentIndex = [GeminiClient sharedClient].authMode;
            [self.authModeSegment addTarget:self action:@selector(authModeChanged:) forControlEvents:UIControlEventValueChanged];
        }
        [cell.contentView addSubview:self.authModeSegment];
        cell.textLabel.text = @"";
    } else if (indexPath.section == 1) {
        if (self.authModeSegment.selectedSegmentIndex == GeminiAuthModeOAuth) {
            if ([[GeminiClient sharedClient] isAuthenticated]) {
                if (indexPath.row == 0) {
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.textLabel.text = @"Bağlı Hesap";
                    cell.detailTextLabel.text = [GeminiClient sharedClient].userEmail.length > 0 ? [GeminiClient sharedClient].userEmail : @"Giriş Yapıldı (Aktif)";
                } else {
                    cell.textLabel.text = @"Hesaptan Çıkış Yap";
                    cell.textLabel.textColor = [UIColor redColor];
                }
            } else {
                cell.textLabel.text = @"🔑 Google Hesabı ile Giriş Yap";
                cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
            }
        } else {
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
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == self.models.count) {
            if (self.isFetchingModels) {
                cell.textLabel.text = @"Modeller alınıyor...";
                cell.textLabel.textColor = [UIColor grayColor];
                UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                [spinner startAnimating];
                cell.accessoryView = spinner;
            } else {
                cell.textLabel.text = @"🔄 Modelleri Yenile (Refresh Models)";
                cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
            }
        } else {
            cell.textLabel.text = self.models[indexPath.row];
            if (indexPath.row == self.selectedModelIndex) {
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
        }
    } else if (indexPath.section == 3) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Hedef Cihaz";
            cell.detailTextLabel.text = @"iPad Mini 1 (iOS 8.4)";
        } else {
            cell.textLabel.text = @"Geliştirici Sürümü";
            cell.detailTextLabel.text = @"v1.8 (OAuth + API Key)";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && self.authModeSegment.selectedSegmentIndex == GeminiAuthModeOAuth) {
        if ([[GeminiClient sharedClient] isAuthenticated]) {
            if (indexPath.row == 1) {
                [self signOutGoogle];
            }
        } else {
            [self startGoogleLogin];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == self.models.count) {
            if (!self.isFetchingModels) {
                [self refreshModelsTapped];
            }
        } else {
            self.selectedModelIndex = indexPath.row;
            [tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

@end
