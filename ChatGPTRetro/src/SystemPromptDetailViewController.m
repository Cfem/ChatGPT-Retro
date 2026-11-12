#import "SystemPromptDetailViewController.h"
#import "OpenAIClient.h"
#import "LocalizationManager.h"

@interface SystemPromptDetailViewController () <UITextFieldDelegate, UITextViewDelegate>

@property (nonatomic, strong) UITextField *titleTextField;
@property (nonatomic, strong) UITextView *contentTextView;

@end

@implementation SystemPromptDetailViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _promptIndex = -1;
        _isEnabled = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = (_promptIndex >= 0) ? LocalizedString(@"edit_prompt_title") : LocalizedString(@"add_prompt_title");

    // Sağ üstte Kırmızı "Sil" butonu (eğer var olan bir talimatsa)
    if (self.promptIndex >= 0) {
        UIBarButtonItem *deleteBtn = [[UIBarButtonItem alloc] initWithTitle:LocalizedString(@"delete_button")
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(deletePromptAction)];
        deleteBtn.tintColor = [UIColor redColor];
        self.navigationItem.rightBarButtonItem = deleteBtn;
    }

    [self setupControls];
}

- (void)setupControls {
    // 1. Başlık Text Kutusu
    _titleTextField = [[UITextField alloc] initWithFrame:CGRectZero];
    _titleTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _titleTextField.placeholder = LocalizedString(@"prompt_title_placeholder");
    _titleTextField.text = self.initialTitle ?: @"";
    _titleTextField.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
    _titleTextField.textColor = [UIColor blackColor];
    _titleTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _titleTextField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    _titleTextField.delegate = self;

    // 2. Metin / Talimat Text Kutusu
    _contentTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    _contentTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _contentTextView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    _contentTextView.textColor = [UIColor blackColor];
    _contentTextView.backgroundColor = [UIColor clearColor];
    _contentTextView.text = self.initialContent ?: @"";
    _contentTextView.delegate = self;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];

    // Sayfadan geri çıkıldığında otomatik kaydet
    [self autoSavePrompt];
}

- (void)autoSavePrompt {
    NSString *title = [self.titleTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *content = [self.contentTextView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // Eğer her ikisi de boşsa ve yeni oluşturuluyorsa hiçbir şey yapma
    if (title.length == 0 && content.length == 0 && self.promptIndex < 0) {
        return;
    }

    // Başlık boşsa ilk satırdan veya içerikten bir başlık türet
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

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2; // Row 0: Başlık, Row 1: Metin
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 0) {
        return 44.0;
    }
    return 240.0; // Geniş rahat talimat yazım alanı
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"PromptEditCell_%ld", (long)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    for (UIView *sub in cell.contentView.subviews) {
        if (sub == self.titleTextField || sub == self.contentTextView) {
            [sub removeFromSuperview];
        }
    }

    CGFloat cellW = cell.contentView.bounds.size.width > 0 ? cell.contentView.bounds.size.width : tableView.bounds.size.width;

    if (indexPath.row == 0) {
        self.titleTextField.frame = CGRectMake(16, 7, cellW - 32, 30);
        [cell.contentView addSubview:self.titleTextField];
    } else {
        self.contentTextView.frame = CGRectMake(12, 6, cellW - 24, 228);
        [cell.contentView addSubview:self.contentTextView];
    }

    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return LocalizedString(@"instructions_placeholder");
}

@end
