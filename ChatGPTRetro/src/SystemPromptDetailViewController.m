#import "SystemPromptDetailViewController.h"
#import "OpenAIClient.h"
#import "LocalizationManager.h"

@interface SystemPromptDetailViewController () <UITextFieldDelegate, UITextViewDelegate>

@property (nonatomic, strong) UITextField *titleTextField;
@property (nonatomic, strong) UITextView *contentTextView;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, assign) BOOL isDeleted;

@end

@implementation SystemPromptDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = (_promptIndex >= 0) ? LocalizedString(@"edit_prompt_title") : LocalizedString(@"add_prompt_title");
    self.view.backgroundColor = [UIColor colorWithRed:239.0/255.0 green:239.0/255.0 blue:244.0/255.0 alpha:1.0]; // Klasik Apple iOS 8 grouped arkaplan gri rengi

    // Sağ üstte Kırmızı "Sil" butonu (eğer var olan bir talimatsa)
    if (self.promptIndex >= 0) {
        UIBarButtonItem *deleteBtn = [[UIBarButtonItem alloc] initWithTitle:LocalizedString(@"delete_button")
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(deletePromptAction)];
        deleteBtn.tintColor = [UIColor redColor];
        self.navigationItem.rightBarButtonItem = deleteBtn;
    }

    [self setupViews];
}

- (void)setupViews {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat margin = 16.0;
    CGFloat topOffset = 84.0; // Üst navigation bar ve margin boşluğu

    // Apple Grouped Kartı (Kenarlardan ve üstten/alttan margin bırakılmış şık beyaz kart)
    _cardView = [[UIView alloc] initWithFrame:CGRectMake(margin, topOffset, w - (margin * 2), h - topOffset - margin)];
    _cardView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _cardView.backgroundColor = [UIColor whiteColor];
    _cardView.layer.cornerRadius = 8.0;
    _cardView.layer.masksToBounds = YES;
    _cardView.layer.borderWidth = 0.5;
    _cardView.layer.borderColor = [UIColor colorWithWhite:0.80 alpha:1.0].CGColor;
    [self.view addSubview:_cardView];

    CGFloat cardW = _cardView.bounds.size.width;

    // 1. Başlık Text Kutusu
    _titleTextField = [[UITextField alloc] initWithFrame:CGRectMake(14, 8, cardW - 28, 36)];
    _titleTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _titleTextField.placeholder = LocalizedString(@"prompt_title_placeholder");
    _titleTextField.text = self.initialTitle ?: @"";
    _titleTextField.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
    _titleTextField.textColor = [UIColor blackColor];
    _titleTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _titleTextField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    _titleTextField.delegate = self;
    [_cardView addSubview:_titleTextField];

    // Klasik iOS Apple Seperator Çizgisi
    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(14, 50, cardW - 14, 0.5)];
    separator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    separator.backgroundColor = [UIColor colorWithWhite:0.80 alpha:1.0]; // Klasik Apple separator rengi
    [_cardView addSubview:separator];

    // 2. Metin / Talimat Text Kutusu (İçeriden rahat marginler, akıcı kaydırma)
    CGFloat textTop = 52.0;
    _contentTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, textTop, cardW - 20, _cardView.bounds.size.height - textTop - 8)];
    _contentTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _contentTextView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    _contentTextView.textColor = [UIColor blackColor];
    _contentTextView.backgroundColor = [UIColor clearColor];
    _contentTextView.text = self.initialContent ?: @"";
    _contentTextView.alwaysBounceVertical = YES;
    _contentTextView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _contentTextView.delegate = self;
    [_cardView addSubview:_contentTextView];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyboardWillChangeFrame:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGRect endFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:endFrame fromView:nil];
    CGFloat bottomInset = self.view.bounds.size.height - converted.origin.y;
    if (bottomInset < 0) bottomInset = 0;

    CGFloat margin = 16.0;
    CGFloat topOffset = 84.0;
    CGFloat cardH = self.view.bounds.size.height - topOffset - margin - bottomInset;
    if (cardH < 120.0) cardH = 120.0;
    _cardView.frame = CGRectMake(margin, topOffset, self.view.bounds.size.width - (margin * 2), cardH);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];

    if (!self.isDeleted) {
        [self autoSavePrompt];
    }
}

- (void)autoSavePrompt {
    NSString *title = [self.titleTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *content = [self.contentTextView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (title.length == 0 && content.length == 0 && self.promptIndex < 0) {
        return;
    }

    if (title.length == 0) {
        if (content.length > 0) {
            NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            NSString *firstLine = lines.firstObject ?: @"";
            if (firstLine.length > 20) {
                title = [firstLine substringToIndex:20];
            } else if (firstLine.length > 0) {
                title = firstLine;
            } else {
                title = @"Talimat";
            }
        } else {
            title = @"Talimat";
        }
    }

    NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
    if (self.promptIndex >= 0 && self.promptIndex < (NSInteger)list.count) {
        NSMutableDictionary *item = list[self.promptIndex];
        item[@"title"] = title;
        item[@"content"] = content;
        [[OpenAIClient sharedClient] saveSystemPromptsList:list];
    } else {
        NSMutableDictionary *newPrompt = [@{
            @"id": self.promptId ?: [[NSUUID UUID] UUIDString],
            @"title": title,
            @"content": content,
            @"enabled": @(self.isEnabled)
        } mutableCopy];
        [list addObject:newPrompt];
        [[OpenAIClient sharedClient] saveSystemPromptsList:list];
        self.promptIndex = list.count - 1;
    }

    if ([self.delegate respondsToSelector:@selector(systemPromptDidSaveOrDelete)]) {
        [self.delegate systemPromptDidSaveOrDelete];
    }
}

- (void)deletePromptAction {
    [self.view endEditing:YES];

    // Ekranın tam ortasında çıkan klasik Apple UIAlertControllerStyleAlert (Vazgeç / Sil)
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LocalizedString(@"prompt_delete_confirm_title")
                                                                   message:LocalizedString(@"prompt_delete_confirm_msg")
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"delete_button")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        self.isDeleted = YES;
        NSMutableArray *list = [OpenAIClient sharedClient].systemPromptsList;
        if (self.promptIndex >= 0 && self.promptIndex < (NSInteger)list.count) {
            [list removeObjectAtIndex:self.promptIndex];
            [[OpenAIClient sharedClient] saveSystemPromptsList:list];
        }
        if ([self.delegate respondsToSelector:@selector(systemPromptDidSaveOrDelete)]) {
            [self.delegate systemPromptDidSaveOrDelete];
        }
        [self.navigationController popViewControllerAnimated:YES];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
