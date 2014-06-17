//
//  TCExploreViewController.m
//  Three Cents
//
//  Created by Bob Spryn on 2/19/14.
//  Copyright (c) 2014 Three Cents, Inc. All rights reserved.
//


#import "UIImage+ColorSquare.h"

#import "TCExploreViewController.h"
#import "TCExploreViewModel.h"
#import "TCExploreSearchHeaderView.h"
#import "TCExploreSearchLoadingCell.h"
#import "TCProfileUserCell.h"
#import "TCExploreHashtagCell.h"
#import "TCHashtag.h"
#import "TCProfileViewController.h"
#import "TCHashtagQuestionListViewController.h"
#import "TCLoadingCell.h"

NS_ENUM(NSUInteger, SearchTableSection) {
    TableSectionResults,
    TableSectionSearchStatus,
    TableSectionCount
};

@interface TCExploreViewController () <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TCExploreSearchHeaderView *searchHeaderView;
@property (nonatomic, strong) TCExploreSearchLoadingCell *searchLoadingCell;
@property (nonatomic, strong) UISearchBar *exploreSearchBar;
@property (nonatomic, strong) UIView *statusBarView;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation TCExploreViewController


- (void)viewDidLoad
{
    [super viewDidLoad];

    @weakify(self);
    // setup the view settings and add subviews
    self.view.backgroundColor = mTCCommonBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.frame style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = mTCLightTanColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    // statusBarView is so we don't have a weird gap where the status bar is while navigation bar is hidden
    [self.view addSubview:self.statusBarView];
    // add and configure the search bar
    self.exploreSearchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, mTCTableViewFrameWidth, 44)];
    self.exploreSearchBar.placeholder = @"Search";
    self.exploreSearchBar.delegate = self;
    [self.exploreSearchBar setBackgroundImage:[UIImage squareImageWithColor:mTCLightTanColor dimension:1] forBarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
    self.tableView.tableHeaderView = self.exploreSearchBar;

    // get a signal for when this view controller is presented
    RACSignal *presented = [[[self.navigationController rac_signalForSelector:@selector(didMoveToParentViewController:)]
        map:^id(RACTuple *values) {
            return @(values.first != nil);
        }]
        setNameWithFormat:@"%@ presented", self];

    // get an app active signal for when the app wakes and sleeps
    RACSignal *appActive = [[[RACSignal
        merge:@[
            [[NSNotificationCenter.defaultCenter rac_addObserverForName:UIApplicationDidBecomeActiveNotification object:nil] mapReplace:@YES],
            [[NSNotificationCenter.defaultCenter rac_addObserverForName:UIApplicationWillResignActiveNotification object:nil] mapReplace:@NO]
        ]]
        startWith:@YES]
        setNameWithFormat:@"%@ appActive", self];

    // bind the result of combining those signals to the active BOOL on the view model.
    RAC(self, viewModel.active) = [[[RACSignal
        combineLatest:@[ presented, appActive ]]
        and]
        setNameWithFormat:@"%@ active", self];
    
    // while active, pass along the signal for entering search mode
    // (When pushing a controller on to the stack, iOS calls `beginEditing` a couple times for some reason
    // so we have to only pay attention to it while active
    RACSignal *enterSearchViewSignal = [[RACSignal
        if:presented
        then:[self rac_signalForSelector:@selector(searchBarTextDidBeginEditing:)]
        else:[RACSignal return:nil]]
        ignore:nil];
    
    // Signal for when the user explicitly taps the cancel button
    RACSignal *cancelSearch = [self rac_signalForSelector:@selector(searchBarCancelButtonClicked:)];
    
    // Signal for whenever the search text changes
    RACSignal *textChange = [[self rac_signalForSelector:@selector(searchBar:textDidChange:)]
        reduceEach:^id(UISearchBar *searchBar, NSString *text) {
            return text;
        }];
    
    // Update the view model search string when text changes or cancel is tapped
    RAC(self, viewModel.searchString) = [RACSignal merge:@[textChange, [cancelSearch mapReplace:@""]]];
    
    // Because the text doesn't get updated when set programatically above
    RAC(self.exploreSearchBar, text) = [cancelSearch mapReplace:@""];
    
    // Combine the entering and exiting search mode
    RACSignal *enterExitSearchModeSignal = [[RACSignal merge:@[[enterSearchViewSignal mapReplace:@YES], [cancelSearch mapReplace:@NO]]] distinctUntilChanged];
    
    // automatically trigger the showing of the cancel buttonwith the enter/exit signal
    [self.exploreSearchBar rac_liftSelector:@selector(setShowsCancelButton:animated:) withSignals:enterExitSearchModeSignal, [RACSignal return:@YES], nil];
    
    // end editing on cancel tap
    [self.exploreSearchBar rac_liftSelector:@selector(endEditing:) withSignals:[RACSignal merge:@[[cancelSearch mapReplace:@YES]]], nil];
    
    // Perform search when search button tapped
    // We don't execute the RACCommand directly because the pointer will flip around
    RACSignal *clickSearch = [self rac_signalForSelector:@selector(searchBarSearchButtonClicked:)];
    // it doesn't matter what value the `clickSearch` signal sends along
    [self.viewModel.searchCommand rac_liftSelector:@selector(execute:) withSignals:clickSearch, nil];

    // show navigation bar when view will disappear
    RACSignal *showWhenDisappearing = [[self rac_signalForSelector:@selector(viewWillDisappear:)]
        mapReplace:@NO];
    
    // combine the enterExit signal with the view disappearing signal
    RACSignal *showHideNavBar = [RACSignal merge:@[enterExitSearchModeSignal, showWhenDisappearing]];
    
    // trigger enterSearchMode: automatically with the showHideNavBar signal
    [self rac_liftSelector:@selector(enterSearchMode:) withSignals:showHideNavBar, nil];

    // register all our cells
    [self.tableView registerClass:[TCExploreSearchHeaderView class] forHeaderFooterViewReuseIdentifier:@"TCExploreSearchHeaderView"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [self.tableView registerClass:[TCProfileUserCell class] forCellReuseIdentifier:@"TCProfileUserCell"];
    [self.tableView registerClass:[TCExploreSearchLoadingCell class] forCellReuseIdentifier:@"TCExploreSearchLoadingCell"];
    [self.tableView registerClass:[TCExploreHashtagCell class] forCellReuseIdentifier:@"TCExploreHashtagCell"];
    [self.tableView registerClass:[TCLoadingCell class] forCellReuseIdentifier:@"TCLoadingCell"];

    // reload the tableview when we receive an update from the view model
    [[RACObserve(self, viewModel.tableUpdateSignal)
        switchToLatest]
        subscribeNext:^(id x) {
            @strongify(self);
            [self.tableView reloadData];
        }];

    // show an error message if we get an error value from the view model
    [[RACObserve(self, viewModel.exploreErrorSignal)
        switchToLatest]
        subscribeNext:^(NSString *errorDescription) {
            [[TWMessageBarManager sharedInstance] showMessageWithTitle:@"Error" description:errorDescription type:TWMessageBarMessageTypeError];
        }];
    
    // handle updating the tableview contentInset and scroll indicators when the keyboard is showing
    [[NSNotificationCenter.defaultCenter rac_addObserverForName:UIKeyboardWillChangeFrameNotification object:nil] subscribeNext:^(NSNotification *notification) {
        @strongify(self);
        NSDictionary *keyboardAnimationDetail = [notification userInfo];
        
        CGRect keyboardEndFrameWindow = [keyboardAnimationDetail[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        
        double keyboardTransitionDuration  = [keyboardAnimationDetail[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        
        CGRect keyboardEndFrameView = [self.view convertRect:keyboardEndFrameWindow fromView:nil];
        
        CGFloat newConstant = (self.view.frame.size.height - keyboardEndFrameView.origin.y);
        
        [UIView animateWithDuration:keyboardTransitionDuration
                              delay:0.0f
                            options:newConstant == 0 ? (6 << 16) : (7 << 16)
                         animations:^{
                             @strongify(self);
                             CGFloat max = MAX(self.view.frame.size.height - keyboardEndFrameView.origin.y, 0);
                             self.tableView.contentInset = UIEdgeInsetsMake(self.tableView.contentInset.top, 0, max, 0);
                             self.tableView.scrollIndicatorInsets = UIEdgeInsetsMake(self.tableView.scrollIndicatorInsets.top, 0, max, 0);
                         }
                         completion:nil];
    }];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    mGARecordScreenView([TCCommon humanNameForClass:[self class]])
}

// utility function leveraged by the reactive code in `viewDidLoad`
- (void) enterSearchMode:(BOOL)enter {
    [self.navigationController setNavigationBarHidden:enter animated:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    return TableSectionCount;
}

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case TableSectionResults:
            if (self.viewModel.tab == TCExploreTabUsers) {
                // cell height calculated taking dynamic text size into account
                return [TCProfileUserCell heightForCellWithTableWidth:mTCTableViewFrameWidth];
            }
        default:
            return 50;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case TableSectionResults:
            // if we want to load popular results return 1, else the count
            return self.viewModel.wantsToLoadPopularResults ? 1 : self.viewModel.results.count;
        case TableSectionSearchStatus:
            return self.viewModel.searchCellState == TCExploreSearchCellStateNone ? 0 : 1;
        default:
            return 0;
    }
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case TableSectionResults: {
            if (self.viewModel.wantsToLoadPopularResults) {
                TCLoadingCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"TCLoadingCell"];
                cell.activityIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyleGray;
                return cell;
            }
            if (self.viewModel.tab == TCExploreTabUsers) {
                TCProfileUserCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TCProfileUserCell"];
                cell.viewModel = [self.viewModel viewModelForUserCellWithIndex:indexPath.row];
                return cell;
            }
            TCExploreHashtagCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TCExploreHashtagCell"];
            TCHashtag *tag = [self.viewModel.results objectAtIndex:indexPath.row];
            cell.primaryLabel.text = [NSString stringWithFormat:@"#%@", tag.displayName];
            return cell;
        }
        case TableSectionSearchStatus:
            return self.searchLoadingCell;
        default:
            return nil;
    }
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == TableSectionSearchStatus) {
        // if our search cell state is ready, then we search when it's tapped
        if (self.viewModel.searchCellState == TCExploreSearchCellStateReady) {
            [self.viewModel.searchCommand execute:nil];
        }
    } else {
        if (self.viewModel.wantsToLoadPopularResults) {
            return;
        }
        // push the appropriate detail view controller depending on the tab
        if (self.viewModel.tab == TCExploreTabUsers) {
            TCProfileViewController *vc = [[TCProfileViewController alloc] initWithStyle:UITableViewStylePlain];
            vc.viewModel = [self.viewModel viewModelForUserProfileWithIndex:indexPath.row];
            [self.navigationController pushViewController:vc animated:YES];
        } else {
            TCHashtagQuestionListViewController *vc = [[TCHashtagQuestionListViewController alloc] initWithStyle:UITableViewStylePlain];
            vc.viewModel = [self.viewModel viewModelForHashTagQuestionListWithIndex:indexPath.row];
            [self.navigationController pushViewController:vc animated:YES];
        }
    }
}

- (void) tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // load the popular results when we see the loading cell
    if (indexPath.section == TableSectionResults && self.viewModel.wantsToLoadPopularResults) {
        [self.viewModel.loadPopularResults execute:nil];
    }
}

- (UIView *) tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == TableSectionResults) {
        return self.searchHeaderView;
    }
    return nil;
}

- (CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == TableSectionResults) {
        return 44;
    }
    return 0;
}

#pragma mark - Lazy view getters

- (TCExploreSearchHeaderView *) searchHeaderView {
    if (!_searchHeaderView) {
        _searchHeaderView = [self.tableView dequeueReusableHeaderFooterViewWithIdentifier:@"TCExploreSearchHeaderView"];
        RAC(_searchHeaderView, viewModel) = [RACObserve(self, viewModel) ignore:nil];
    }
    return _searchHeaderView;
}

- (TCExploreSearchLoadingCell *) searchLoadingCell {
    if (!_searchLoadingCell) {
        _searchLoadingCell = [self.tableView dequeueReusableCellWithIdentifier:@"TCExploreSearchLoadingCell"];
        _searchLoadingCell.viewModel = self.viewModel;
    }
    return _searchLoadingCell;
}

- (UIView *) statusBarView {
    if (!_statusBarView) {
        _statusBarView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, [UIApplication sharedApplication].statusBarFrame.size.height)];
        _statusBarView.backgroundColor = mTCCommonBackgroundColor;
    }
    return _statusBarView;
}

@end
