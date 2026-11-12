#import "ChatHistorySidebarViewController.h"
#import "ChatHistoryManager.h"
#import "LocalizationManager.h"

@interface ChatHistorySidebarViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *createNewChatButton;

@end

@implementation ChatHistorySidebarViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = LocalizedString(@"history_title");
    self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
                                                                                           target:self
                                                                                           action:@selector(newChatAction)];

    [self setupNewChatButton];
    [self setupTableView];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(languageDidChange:)
                                                 name:kLanguageDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)languageDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.title = LocalizedString(@"history_title");
        [self.createNewChatButton setTitle:LocalizedString(@"new_chat_button") forState:UIControlStateNormal];
        [self.tableView reloadData];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadHistory];
}

- (void)reloadHistory {
    [self.tableView reloadData];
}

- (void)setupNewChatButton {
    CGFloat w = self.view.bounds.size.width;
    _createNewChatButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _createNewChatButton.frame = CGRectMake(12, 10, w - 24, 42);
    _createNewChatButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _createNewChatButton.backgroundColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
    [_createNewChatButton setTitle:LocalizedString(@"new_chat_button") forState:UIControlStateNormal];
    [_createNewChatButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _createNewChatButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15.0];
    _createNewChatButton.layer.cornerRadius = 8.0;
    [_createNewChatButton addTarget:self action:@selector(newChatAction) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_createNewChatButton];
}

- (void)setupTableView {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat topOffset = 60.0;

    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, topOffset, w, h - topOffset) style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
    _tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:_tableView];
}

- (void)newChatAction {
    if ([self.delegate respondsToSelector:@selector(sidebarDidRequestNewChat)]) {
        [self.delegate sidebarDidRequestNewChat];
    }
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [ChatHistoryManager sharedManager].sessions.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 62.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"SidebarSessionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15.0];
        cell.detailTextLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:12.0];
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }

    ChatSession *session = [ChatHistoryManager sharedManager].sessions[indexPath.row];
    BOOL isActive = (session == [ChatHistoryManager sharedManager].activeSession);

    cell.textLabel.text = session.title ?: LocalizedString(@"new_chat_title");
    cell.textLabel.textColor = isActive ? [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0] : [UIColor blackColor];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"dd MMM HH:mm";
    NSString *dateStr = [fmt stringFromDate:session.updatedAt];
    cell.detailTextLabel.text = [NSString stringWithFormat:LocalizedString(@"msg_count_format"), (unsigned long)session.messages.count, dateStr ?: @""];

    cell.accessoryType = isActive ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ChatSession *session = [ChatHistoryManager sharedManager].sessions[indexPath.row];
    [[ChatHistoryManager sharedManager] switchToSession:session];
    [self.tableView reloadData];

    if ([self.delegate respondsToSelector:@selector(sidebarDidSelectSession:)]) {
        [self.delegate sidebarDidSelectSession:session];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [[ChatHistoryManager sharedManager] deleteSessionAtIndex:indexPath.row];
        [tableView reloadData];
        // Sadece arka plandaki aktif sohbeti güncelle, sidebar'ı kapatma!
        if ([self.delegate respondsToSelector:@selector(sidebarDidDeleteSession:)]) {
            [self.delegate sidebarDidDeleteSession:[ChatHistoryManager sharedManager].activeSession];
        }
    }
}

@end
