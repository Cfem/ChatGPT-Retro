#import "SystemPromptDetailViewController.h"
#import "OpenAIClient.h"
#import "LocalizationManager.h"

@interface SystemPromptDetailViewController () <UITextFieldDelegate, UITextViewDelegate>

@property (nonatomic, strong) UITextField *titleTextField;
@property (nonatomic, strong) UITextView *contentTextView;
@property (nonatomic, strong) UIView *titleBox;
@property (nonatomic, strong) UIView *contentBox;
@property (nonatomic, assign) BOOL isDeleted;

@end

@implementation SystemPromptDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = (_promptIndex >= 0) ? LocalizedString(@"edit_prompt_title") : LocalizedString(@"add_prompt_title");
    self.view.backgroundColor = [UIColor colorWithRed:239.0/255.0 green:239.0/255.0 blue:244.0/255.0 alpha:1.0]; // Apple Grouped TableView arka planı

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
    CGFloat margin = 16.0;
    CGFloat boxW = w - (margin * 2);
    CGFloat topOffset = 76.0;

    // 1. KUTU: BAŞLIK KUTUSU (Apple Grouped Kart)
    _titleBox = [[UIView alloc] initWithFrame:CGRectMake(margin, topOffset, boxW, 44.0)];
    _titleBox.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _titleBox.backgroundColor = [UIColor whiteColor];
    _titleBox.layer.cornerRadius = 8.0;
    _titleBox.layer.masksToBounds = YES;
    _titleBox.layer.borderWidth = 0.5;
    _titleBox.layer.borderColor = [UIColor colorWithWhite:0.78 alpha:1.0].CGColor;
    [self.view addSubview:_titleBox];

    _titleTextField = [[UITextField alloc] initWithFrame:CGRectMake(14, 4, boxW - 28, 36)];
    _titleTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _titleTextField.placeholder = LocalizedString(@"prompt_title_placeholder");
    _titleTextField.text = self.initialTitle ?: @"";
    _titleTextField.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
    _titleTextField.textColor = [UIColor blackColor];
    _titleTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _titleTextField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    _titleTextField.delegate = self;
    [_titleBox addSubview:_titleTextField];

    // 2. KUTU: METİN GÖVDESİ KUTUSU (Ayrı Kart, klavye ile dinamik boylanan)
    CGFloat contentTop = topOffset + 44.0 + 12.0; // İki kutu arasında net 12px boşluk
    CGFloat contentH = self.view.bounds.size.height - contentTop - margin;
    _contentBox = [[UIView alloc] initWithFrame:CGRectMake(margin, contentTop, boxW, contentH)];
    _contentBox.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _contentBox.backgroundColor = [UIColor whiteColor];
    _contentBox.layer.cornerRadius = 8.0;
    _contentBox.layer.masksToBounds = YES;
    _contentBox.layer.borderWidth = 0.5;
    _contentBox.layer.borderColor = [UIColor colorWithWhite:0.78 alpha:1.0].CGColor;
    [self.view addSubview:_contentBox];

    _contentTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 8, boxW - 20, _contentBox.bounds.size.height - 16)];
    _contentTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _contentTextView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    _contentTextView.textColor = [UIColor blackColor];
    _contentTextView.backgroundColor = [UIColor clearColor];
    _contentTextView.text = self.initialContent ?: @"";
    _contentTextView.alwaysBounceVertical = YES;
    _contentTextView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _contentTextView.delegate = self;
    [_contentBox addSubview:_contentTextView];
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
    CGFloat contentTop = 76.0 + 44.0 + 12.0;
    CGFloat boxH = self.view.bounds.size.height - contentTop - margin - bottomInset;
    if (boxH < 100.0) boxH = 100.0;
    _contentBox.frame = CGRectMake(margin, contentTop, self.view.bounds.size.width - (margin * 2), boxH);
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
