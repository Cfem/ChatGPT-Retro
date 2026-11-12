#import "SystemPromptDetailViewController.h"
#import "OpenAIClient.h"
#import "LocalizationManager.h"

@interface SystemPromptDetailViewController () <UITextFieldDelegate, UITextViewDelegate>

@property (nonatomic, strong) UITextField *titleTextField;
@property (nonatomic, strong) UITextView *contentTextView;

@end

@implementation SystemPromptDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = (_promptIndex >= 0) ? LocalizedString(@"edit_prompt_title") : LocalizedString(@"add_prompt_title");
    self.view.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];

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
    // Klavye bildirimleri
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // Üstte beyaz form kartı
    UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(0, 74, w, h - 74)];
    cardView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    cardView.backgroundColor = [UIColor whiteColor];
    cardView.tag = 5001;
    [self.view addSubview:cardView];

    // 1. Başlık Text Kutusu
    _titleTextField = [[UITextField alloc] initWithFrame:CGRectMake(16, 8, w - 32, 34)];
    _titleTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _titleTextField.placeholder = LocalizedString(@"prompt_title_placeholder");
    _titleTextField.text = self.initialTitle ?: @"";
    _titleTextField.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
    _titleTextField.textColor = [UIColor blackColor];
    _titleTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _titleTextField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    _titleTextField.delegate = self;
    [cardView addSubview:_titleTextField];

    // İki kutu arasındaki ince Apple çizgisi (Separator)
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(16, 48, w - 16, 0.5)];
    line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    line.backgroundColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    [cardView addSubview:line];

    // 2. Metin / Talimat Text Kutusu (Rahat kaydırılabilen, klavye gelince boyutu küçülen UITextView)
    _contentTextView = [[UITextView alloc] initWithFrame:CGRectMake(12, 52, w - 24, cardView.bounds.size.height - 56)];
    _contentTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _contentTextView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    _contentTextView.textColor = [UIColor blackColor];
    _contentTextView.backgroundColor = [UIColor clearColor];
    _contentTextView.text = self.initialContent ?: @"";
    _contentTextView.alwaysBounceVertical = YES;
    _contentTextView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _contentTextView.delegate = self;
    [cardView addSubview:_contentTextView];
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

    UIView *cardView = [self.view viewWithTag:5001];
    CGFloat cardH = self.view.bounds.size.height - 74 - bottomInset;
    cardView.frame = CGRectMake(0, 74, self.view.bounds.size.width, cardH);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];

    [self autoSavePrompt];
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

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:LocalizedString(@"prompt_delete_confirm_title")
                                                                     message:LocalizedString(@"prompt_delete_confirm_msg")
                                                              preferredStyle:UIAlertControllerStyleActionSheet];

    [confirm addAction:[UIAlertAction actionWithTitle:LocalizedString(@"delete_button")
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *action) {
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

    [confirm addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button")
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];

    confirm.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:confirm animated:YES completion:nil];
}

@end
