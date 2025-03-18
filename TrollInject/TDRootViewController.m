#import "TDRootViewController.h"
#import "TDUtils.h"

@implementation TDRootViewController

- (void)loadView {
    [super loadView];

    self.apps = appList();
    self.title = @"TrollInject!";
	self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(about:)];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshApps:) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
}

- (void)about:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TrollInject" message:@"by frefire\nFile signer by TrollFool\nUI by TrollDecrypt" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshApps:(UIRefreshControl *)refreshControl {
    self.apps = appList();
    [self.tableView reloadData];
    [refreshControl endRefreshing];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { 
    return self.apps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"AppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];

    NSDictionary *app = self.apps[indexPath.row];

    cell.textLabel.text = app[@"name"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", app[@"version"], app[@"bundleID"]];
    cell.imageView.image = [UIImage _applicationIconImageForBundleIdentifier:app[@"bundleID"] format:iconFormat() scale:[UIScreen mainScreen].scale];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0f;
}

- (void)deselectRow {
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    NSDictionary *app = self.apps[indexPath.row];
    
    UIAlertController *appSelectAlert = [UIAlertController alertControllerWithTitle:app[@"name"] message:app[@"bundleID"] preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *peekStartupInfoAction = [UIAlertAction actionWithTitle:@"Peek startup info" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        peekStartupInfo(app);
        [self deselectRow];
    }];
    [appSelectAlert addAction:peekStartupInfoAction];
    
    UIAlertAction *peekInfoAction = [UIAlertAction actionWithTitle:@"Peek info" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        peekInfo(app);
        [self deselectRow];
    }];
    [appSelectAlert addAction:peekInfoAction];
    
    UIAlertAction *launchWithDylibAlert = [UIAlertAction actionWithTitle:@"Launch with Dylib" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        launchWithDylib(app);
        [self deselectRow];
    }];
    [appSelectAlert addAction:launchWithDylibAlert];
    
    UIAlertAction *injectRunningWithDylibAlert = [UIAlertAction actionWithTitle:@"Inject running with Dylib" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        injectRunningWithDylib(app);
        [self deselectRow];
    }];
    [appSelectAlert addAction:injectRunningWithDylibAlert];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [self deselectRow];
    }];
    [appSelectAlert addAction:cancelAction];
    
    appSelectAlert.popoverPresentationController.sourceView = tableView;
    appSelectAlert.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:appSelectAlert animated:YES completion:nil];
}

@end
