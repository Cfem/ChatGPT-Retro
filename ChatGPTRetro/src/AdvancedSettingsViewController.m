#import "AdvancedSettingsViewController.h"
#import "OpenAIClient.h"
#import "LocalizationManager.h"

@interface AdvancedSettingsViewController ()

@property (nonatomic, strong) UISwitch *promptCachingSwitch;
@property (nonatomic, strong) UISwitch *truncateAssistantSwitch;
@property (nonatomic, strong) UISwitch *keywordFilteringSwitch;

@property (nonatomic, strong) UISlider *tokenTurnsSlider;
@property (nonatomic, strong) UILabel *tokenTurnsValueLabel;

@end

@implementation AdvancedSettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = LocalizedString(@"adv_screen_title");

    UIColor *openAIGreen = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];

    _promptCachingSwitch = [[UISwitch alloc] init];
    _promptCachingSwitch.onTintColor = openAIGreen;
    _promptCachingSwitch.on = [OpenAIClient sharedClient].enablePromptCaching;
    [_promptCachingSwitch addTarget:self action:@selector(promptCachingChanged:) forControlEvents:UIControlEventValueChanged];

    _truncateAssistantSwitch = [[UISwitch alloc] init];
    _truncateAssistantSwitch.onTintColor = openAIGreen;
    _truncateAssistantSwitch.on = [OpenAIClient sharedClient].enableTruncateAssistant;
    [_truncateAssistantSwitch addTarget:self action:@selector(truncateAssistantChanged:) forControlEvents:UIControlEventValueChanged];

    _keywordFilteringSwitch = [[UISwitch alloc] init];
    _keywordFilteringSwitch.onTintColor = openAIGreen;
    _keywordFilteringSwitch.on = [OpenAIClient sharedClient].enableKeywordFiltering;
    [_keywordFilteringSwitch addTarget:self action:@selector(keywordFilteringChanged:) forControlEvents:UIControlEventValueChanged];

    _tokenTurnsSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _tokenTurnsSlider.minimumValue = 1.0f;
    _tokenTurnsSlider.maximumValue = 20.0f;
    _tokenTurnsSlider.continuous = YES;
    _tokenTurnsSlider.minimumTrackTintColor = openAIGreen;
    _tokenTurnsSlider.value = (float)[OpenAIClient sharedClient].maxHistoryTurns;
    [_tokenTurnsSlider addTarget:self action:@selector(tokenTurnsSliderChanged:) forControlEvents:UIControlEventValueChanged];

    _tokenTurnsValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _tokenTurnsValueLabel.textAlignment = NSTextAlignmentRight;
    _tokenTurnsValueLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:14.0];
    _tokenTurnsValueLabel.textColor = openAIGreen;
    [self updateTokenTurnsLabelText];
}

- (void)promptCachingChanged:(UISwitch *)sender {
    [OpenAIClient sharedClient].enablePromptCaching = sender.isOn;
}

- (void)truncateAssistantChanged:(UISwitch *)sender {
    [OpenAIClient sharedClient].enableTruncateAssistant = sender.isOn;
}

- (void)keywordFilteringChanged:(UISwitch *)sender {
    [OpenAIClient sharedClient].enableKeywordFiltering = sender.isOn;
}

- (void)updateTokenTurnsLabelText {
    NSInteger turns = (NSInteger)roundf(self.tokenTurnsSlider.value);
    NSString *format = LocalizedString(@"turns_count_format");
    self.tokenTurnsValueLabel.text = [NSString stringWithFormat:format, (long)turns];
}

- (void)tokenTurnsSliderChanged:(UISlider *)sender {
    NSInteger snapped = (NSInteger)roundf(sender.value);
    [sender setValue:(float)snapped animated:NO];
    [OpenAIClient sharedClient].maxHistoryTurns = snapped;
    [self updateTokenTurnsLabelText];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4; // 1: Prompt Caching, 2: Truncate Assistant, 3: Token Slider, 4: Keyword Filtering
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return LocalizedString(@"adv_prompt_caching_desc");
    if (section == 1) return LocalizedString(@"adv_truncate_assistant_desc");
    if (section == 2) return LocalizedString(@"adv_token_counter_desc");
    if (section == 3) return LocalizedString(@"adv_keyword_filtering_desc");
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) {
        return 70.0; // Slider satırı
    }
    return 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"AdvCell_%ld", (long)indexPath.section];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.text = nil;

    for (UIView *sub in cell.contentView.subviews) {
        if (sub == self.tokenTurnsSlider || sub == self.tokenTurnsValueLabel) {
            [sub removeFromSuperview];
        }
    }

    CGFloat w = cell.contentView.bounds.size.width > 0 ? cell.contentView.bounds.size.width : tableView.bounds.size.width;

    if (indexPath.section == 0) {
        cell.textLabel.text = LocalizedString(@"adv_prompt_caching_title");
        cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
        cell.accessoryView = self.promptCachingSwitch;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = LocalizedString(@"adv_truncate_assistant_title");
        cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
        cell.accessoryView = self.truncateAssistantSwitch;
    } else if (indexPath.section == 2) {
        UILabel *titleLbl = [cell.contentView viewWithTag:8801];
        if (!titleLbl) {
            titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, w * 0.5, 22)];
            titleLbl.tag = 8801;
            titleLbl.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
            titleLbl.textColor = [UIColor blackColor];
            titleLbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
            [cell.contentView addSubview:titleLbl];
        }
        titleLbl.text = LocalizedString(@"adv_token_counter_title");

        self.tokenTurnsValueLabel.frame = CGRectMake(w - 140, 8, 124, 22);
        self.tokenTurnsValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [self updateTokenTurnsLabelText];
        [cell.contentView addSubview:self.tokenTurnsValueLabel];

        self.tokenTurnsSlider.frame = CGRectMake(16, 36, w - 32, 28);
        self.tokenTurnsSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:self.tokenTurnsSlider];
    } else if (indexPath.section == 3) {
        cell.textLabel.text = LocalizedString(@"adv_keyword_filtering_title");
        cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
        cell.accessoryView = self.keywordFilteringSwitch;
    }

    return cell;
}

@end
