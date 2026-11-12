#import "ModelSelectionViewController.h"
#import "OpenAIClient.h"
#import "LocalizationManager.h"

@interface ModelSelectionViewController ()

@property (nonatomic, strong) NSArray *modelsList;
@property (nonatomic, assign) BOOL isFetching;
@property (nonatomic, strong) UIActivityIndicatorView *refreshSpinner;

@end

@implementation ModelSelectionViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = LocalizedString(@"models_screen_title");

    // Canlı Modelleri Çek / Güncelle butonu (Sağ üstte şık refresh ikonu veya spinner)
    _refreshSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _refreshSpinner.hidesWhenStopped = YES;

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                target:self
                                                                                action:@selector(refreshModelsAction)];
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [self loadInitialModels];
}

- (void)loadInitialModels {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *cached = [defaults arrayForKey:@"OpenAIClientCachedModels"];
    if (cached.count > 0) {
        _modelsList = cached;
    } else {
        _modelsList = @[
            @"gpt-4o",
            @"gpt-4o-mini",
            @"gpt-5",
            @"gpt-5-mini",
            @"gpt-6-luna",
            @"o1",
            @"o3",
            @"o3-mini",
            @"o4-mini"
        ];
    }
    [self.tableView reloadData];
}

- (void)refreshModelsAction {
    if (self.isFetching) return;

    self.isFetching = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.refreshSpinner];
    [self.refreshSpinner startAnimating];

    [[OpenAIClient sharedClient] fetchAvailableModelsWithCompletion:^(NSArray *models, NSError *error) {
        self.isFetching = NO;
        [self.refreshSpinner stopAnimating];

        UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                    target:self
                                                                                    action:@selector(refreshModelsAction)];
        self.navigationItem.rightBarButtonItem = refreshBtn;

        if (!error && models.count > 0) {
            self.modelsList = models;
            [self.tableView reloadData];
        } else if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Hata"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"ok_button") style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.modelsList.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return LocalizedString(@"section_model");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"ModelCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }

    NSString *modelName = self.modelsList[indexPath.row];
    cell.textLabel.text = modelName;
    cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];

    NSString *currentModel = [OpenAIClient sharedClient].selectedModel ?: @"gpt-4o-mini";
    if ([modelName isEqualToString:currentModel]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        cell.textLabel.textColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.textColor = [UIColor blackColor];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSString *chosen = self.modelsList[indexPath.row];
    [[OpenAIClient sharedClient] saveSelectedModel:chosen];
    [self.tableView reloadData];

    if ([self.delegate respondsToSelector:@selector(modelSelectionDidSelectModel:)]) {
        [self.delegate modelSelectionDidSelectModel:chosen];
    }
}

@end
