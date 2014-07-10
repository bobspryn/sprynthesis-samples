//
//  TCExploreViewModel.m
//  Three Cents
//
//  Created by Bob Spryn on 4/6/14.
//  Copyright (c) 2014 Three Cents, Inc. All rights reserved.
//

#import "TCExploreViewModel.h"
#import "TCProfileFollowerFolloweeCellViewModel.h"
#import "TCAPI+Users.h"
#import "TCAPI+Hashtags.h"
#import "TCProfileViewModel.h"
#import "TCHashtagQuestionListViewModel.h"

@interface TCExploreViewModel ()

// More discrete properties for internal use
// Internally we break things down between popular results vs search results
// and hashtags vs users
// The view controller need not concern itself with this
@property (nonatomic, strong) NSOrderedSet *popularHashtags;
@property (nonatomic, strong) NSOrderedSet *popularUsers;
@property (nonatomic, strong) NSOrderedSet *hashtagSearchResults;
@property (nonatomic, strong) NSOrderedSet *userSearchResults;
@property (nonatomic, assign) enum TCExploreSearchCellState hashtagsSearchCellState;
@property (nonatomic, assign) enum TCExploreSearchCellState usersSearchCellState;
@property (nonatomic, strong) RACCommand *loadPopularTagResults;
@property (nonatomic, strong) RACCommand *loadPopularUserResults;
@property (nonatomic, strong) RACCommand *searchCommand;
@property (nonatomic, assign) BOOL wantsToLoadPopularHastagResults;
@property (nonatomic, assign) BOOL wantsToLoadPopularUserResults;

// a command for fetching local results
@property (nonatomic, strong) RACCommand *fetchDBObjects;

// read write some of the header properties
@property (nonatomic, strong) NSOrderedSet *results;
@property (nonatomic, strong) RACSignal *exploreErrorSignal;
@property (nonatomic, assign) enum TCExploreSearchCellState searchCellState;
@property (nonatomic, strong) RACSignal *tableUpdateSignal;
@property (nonatomic, assign) BOOL wantsToLoadPopularResults;
@property (nonatomic, strong) RACCommand *loadPopularResults;

@end

@implementation TCExploreViewModel

- (id) init {
    self = [super init];
    if (!self) return nil;
    
    // start off on the hashtags tab
    self.tab = TCExploreTabHashtags;

    @weakify(self);

    //
    // Explore
    //
    
    // a signal for when the tab state changes
    RACSignal *tabState = [RACObserve(self, tab) distinctUntilChanged];
    
    // signal for whether or not we are currently in search mode (whether or not the search string is empty)
    RACSignal *inSearchMode = [RACObserve(self, searchString)
        map:^id(NSString *searchString) {
            return @(searchString && searchString.length > 0);
        }];
    

    //
    // Popular tag results
    //
    
    // Command for loading the popular tag results in
    self.loadPopularTagResults = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(id input) {
        return [[TCAPI getPopularHashtags]
            map:^id(TCAPIRKResponse *response) {
                return [NSOrderedSet orderedSetWithArray:response.result.array];
            }];
    }];
    
    // Observes the results of the popularTagResults command
    RAC(self, popularHashtags) = [[self.loadPopularTagResults.executionSignals switchToLatest]
        startWith:[NSOrderedSet orderedSet]];

    // whenever it finishes executing we want to change the loading state, skip the initial value of NO
    RACSignal *finishedLoadingPopularTags = [[self.loadPopularTagResults.executing ignore:@YES]
        skip:1];
    
    // grab a signal for when the view model becomes active
    RACSignal *viewWillAppearYES = [self.didBecomeActiveSignal
        mapReplace:@YES];
    
    // we want to get the results whenever we enter explore mode, and not after we've finished retrieving them
    // merge the signals of becoming active and finishing loading tags
    RAC(self, wantsToLoadPopularHastagResults) = [RACSignal merge:@[viewWillAppearYES, finishedLoadingPopularTags]];

    
    //
    // Popular user results
    //
    
    // command for loading in the popular users from the API
    self.loadPopularUserResults = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(id input) {
        return [[TCAPI getPopularUsers]
            map:^id(TCAPIRKResponse *response) {
                return [NSOrderedSet orderedSetWithArray:response.result.array];
            }];
    }];
    
    // observes the results of the loadPopularUserResults command
    RAC(self, popularUsers) = [[self.loadPopularUserResults.executionSignals switchToLatest]
        startWith:[NSOrderedSet orderedSet]];

    // whenever it finishes executing we want to change the loading state, skip the initial value of NO
    RACSignal *finishedLoadingPopularUsers = [[self.loadPopularUserResults.executing ignore:@YES]
        skip:1];

    // we want to get the results whenever we enter explore mode, and not after we've finished retrieving them
    RAC(self, wantsToLoadPopularUserResults) = [RACSignal merge:@[viewWillAppearYES, finishedLoadingPopularUsers]];
    
    // swap the command whenever the tab state changes
    RAC(self, loadPopularResults) = [RACSignal if:tabState
        then:RACObserve(self, loadPopularUserResults)
        else:RACObserve(self, loadPopularTagResults)];
    
    // the generic version of wants to load
    // never if in search mode, otherwise observe appropriate internal property
    RAC(self, wantsToLoadPopularResults) = [RACSignal if:inSearchMode
        then:[RACSignal return:@NO]
        else:[RACSignal if:tabState
            then:RACObserve(self, wantsToLoadPopularUserResults)
            else:RACObserve(self, wantsToLoadPopularHastagResults)]];
    

    //
    // Searching
    //
    
    
    // the local user search request
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:[TCUser entityName]];
    
    // core data RACCommand for immediately returning matching users
    self.fetchDBObjects = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(NSString *searchString) {
        return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
            request.predicate = [NSPredicate predicateWithFormat:@"%K CONTAINS[cd] %@ OR %K CONTAINS[cd] %@ OR %K CONTAINS[cd] %@", TCUserAttributes.username, searchString, TCUserAttributes.firstName, searchString, TCUserAttributes.lastName, searchString];
            NSError *error;
            NSArray *objects = [TCMainContext executeFetchRequest:request error:&error];
            if (error) {
                [subscriber sendError:error];
            } else {
                [subscriber sendNext:[NSOrderedSet orderedSetWithArray:objects]];
                [subscriber sendCompleted];
            }
            return nil;
        }];
    }];
    
    // API RACCommand for searching for users
    RACCommand *searchForUsers = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(id _) {
        @strongify(self);
        return [[TCAPI searchForUsersWithQueryString:self.searchString]
            map:^id(TCAPIRKResponse *apiResponse) {
                return [NSOrderedSet orderedSetWithArray:apiResponse.result.array];
            }];
    }];
    // Allow them to execute a new search before the other one finishes (we'll only observe the latest)
    searchForUsers.allowsConcurrentExecution = YES;
    
    // API RACCommand for searching for hashtags
    RACCommand *searchForHashtags = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(id _) {
        @strongify(self);
        return [[TCAPI searchForHashtagsWithQueryString:self.searchString]
            map:^id(TCAPIRKResponse *apiResponse) {
                return [NSOrderedSet orderedSetWithArray:apiResponse.result.array];
            }];
    }];
    // Allow them to execute a new search before the other one finishes (we'll only observe the latest)
    searchForHashtags.allowsConcurrentExecution = YES;

    // a pointer to whichever command we need to be executing
    RAC(self, searchCommand) = [RACSignal
        if:tabState
            then:[RACSignal return:searchForUsers]
        else:[RACSignal return:searchForHashtags]];
    
    // trigger the fetch of core data objects when the search string changes
    RACSignal *dbSearchSignal = [RACObserve(self, searchString)
        filter:^BOOL(NSString *searchString) {
            return searchString && searchString.length > 0;
        }];
   
    // trigger the execute
    [self.fetchDBObjects rac_liftSelector:@selector(execute:) withSignals:dbSearchSignal, nil];
    
    // when the searchString goes back to empty, we want to purge core data results
    RACSignal *emptyDBFetchResults = [[RACObserve(self, searchString)
        filter:^BOOL(NSString *searchString) {
            return searchString.length == 0;
        }]
        mapReplace:[NSOrderedSet orderedSet]];
    
    // Real core data results and the purge signal merged
    RACSignal *fetchDBResults = [RACSignal merge:@[[self.fetchDBObjects.executionSignals switchToLatest], emptyDBFetchResults]];

    // Search User API results and a purge signal when the search string goes to empty
    RACSignal *apiUserSearchResults = [[RACSignal merge:@[[searchForUsers.executionSignals switchToLatest], [RACObserve(self, searchString) mapReplace:[NSOrderedSet orderedSet]]]]
        startWith:[NSOrderedSet orderedSet]];
    
    // Combine the latest core data and API results
    RAC(self, userSearchResults) = [RACSignal combineLatest:@[fetchDBResults, apiUserSearchResults]
        reduce:^id (NSOrderedSet *dbResults, NSOrderedSet *apiResults){
            NSMutableOrderedSet *combined = [dbResults mutableCopy];
            [combined unionOrderedSet:apiResults];
            return combined;
        }];

    // Search Hash API results and a purge signal when the search string goes to empty
    RAC(self, hashtagSearchResults) = [[RACSignal merge:@[[searchForHashtags.executionSignals switchToLatest], [RACObserve(self, searchString) mapReplace:[NSOrderedSet orderedSet]]]]
        startWith:[NSOrderedSet orderedSet]];
    
    //
    // Generic results property
    //
    
    // tabState is either 0 or 1, so it works in a nice if signal
    // automatically toggles the `results` property to the appropriate data based on tab and search state
    RAC(self, results) = [[RACSignal
        if:tabState
            then:[RACSignal
                if:inSearchMode
                    then:RACObserve(self, userSearchResults)
                    else:RACObserve(self, popularUsers)]
            else:[RACSignal
                if:inSearchMode
                    then:RACObserve(self, hashtagSearchResults)
                    else:RACObserve(self, popularHashtags)]]
        startWith:[NSOrderedSet orderedSet]];
    

    //
    // Generic search cell state
    //
    
    
    // signal returning cell state when search string changes
    RACSignal *searchStringDrivenCellStateChange = [RACObserve(self, searchString)
        map:^id(NSString *searchString) {
            return searchString && searchString.length != 0 ? @(TCExploreSearchCellStateReady) : @(TCExploreSearchCellStateNone);
        }];
    
    // public property – state for the current display of the search/loading cell
    RAC(self, searchCellState) = [RACSignal
        if:tabState
            then:RACObserve(self, usersSearchCellState)
            else:RACObserve(self, hashtagsSearchCellState)];
    
    // public property – text for the search cell
    RAC(self, searchLoadingCellText) = [[RACSignal combineLatest:@[[RACObserve(self, searchCellState) distinctUntilChanged], RACObserve(self, searchString)]
        reduce:^id (NSNumber *state, NSString *searchString){
            return state;
        }]
        flattenMap:^RACStream *(NSNumber *state) {
            @strongify(self);
            return [self rac_liftSelector:@selector(textForSearchLoadingCellForState:) withSignals:[RACSignal return:state], nil];
        }];


    //
    // hashtag search cell state
    //
    
    // returns a value when searching hashtags just started
    RACSignal *searchingHashtagsCellState = [[searchForHashtags.executing ignore:@NO]
        mapReplace:@(TCExploreSearchCellStateSearching)];
    
    // returns a value when searching hashtags ends
    RACSignal *finishedSearchingHashtagsCellState = [[searchForHashtags.executionSignals switchToLatest]
        map:^id(NSOrderedSet *set) {
            return set.count == 0 ? @(TCExploreSearchCellStateNoResults) : @(TCExploreSearchCellStateNone);
        }];
    
    // returns a value when there's an error in the command
    RACSignal *errorSearchingHashtagsCellState = [searchForHashtags.errors
        mapReplace:@(TCExploreSearchCellStateReady)];
    
    // the state for the hashtags search/loading cell is a merge of a bunch of different signals
    RAC(self, hashtagsSearchCellState) = [RACSignal merge:@[searchStringDrivenCellStateChange, searchingHashtagsCellState, finishedSearchingHashtagsCellState, errorSearchingHashtagsCellState]];
    

    //
    // users search cell state
    //
    
    // returns a value when searching hashtags just started
    RACSignal *searchingUsersCellState = [[searchForUsers.executing ignore:@NO]
        mapReplace:@(TCExploreSearchCellStateSearching)];
    
    // returns a value when searching hashtags ends
    RACSignal *finishedSearchingUsersCellState = [[searchForUsers.executionSignals switchToLatest]
        map:^id(NSOrderedSet *set) {
            return set.count == 0 ? @(TCExploreSearchCellStateNoResults) : @(TCExploreSearchCellStateNone);
        }];
    
    // returns a value when there's an error in the command
    RACSignal *errorSearchingUsersCellState = [searchForUsers.errors
        mapReplace:@(TCExploreSearchCellStateReady)];
    
    // the state for the hashtags search/loading cell is a merge of a bunch of different signals
    RAC(self, usersSearchCellState) = [RACSignal merge:@[searchStringDrivenCellStateChange, searchingUsersCellState, finishedSearchingUsersCellState, errorSearchingUsersCellState]];

    
    //
    // table update signal
    //
    
    // buffering with a 0 interval coalesces table updates
    self.tableUpdateSignal = [[RACSignal merge:@[RACObserve(self, results), RACObserve(self, searchCellState), RACObserve(self, wantsToLoadPopularResults)]]
        bufferWithTime:0 onScheduler:[RACScheduler mainThreadScheduler]];

    self.exploreErrorSignal = [[RACSignal merge:@[self.loadPopularTagResults.errors,
                                                 self.loadPopularUserResults.errors,
                                                 [RACObserve(self, searchCommand.errors) switchToLatest]]]
        map:^id(NSError *error) {
            if ([error.domain isEqualToString:kThreeCentsErrorDomain]) {
                return error.localizedDescription;
            } else {
                return [TCCommon localizedDescriptionForError:kThreeCentsErrorGenericNetworkError];
            }
        }];
    
    return self;
}

- (NSString *) textForSearchLoadingCellForState:(enum TCExploreSearchCellState) state {
    switch (state) {
        case TCExploreSearchCellStateNoResults:
            return @"No results found";
        case TCExploreSearchCellStateReady:
            return [NSString stringWithFormat:@"Search for \"%@\"", self.searchString];
        case TCExploreSearchCellStateSearching:
            return @"Searching";
        default:
            return nil;
    }
}

- (TCProfileFollowerFolloweeCellViewModel *) viewModelForUserCellWithIndex:(NSUInteger)index {
    TCUser *user = [self.results objectAtIndex:index];
    TCProfileFollowerFolloweeCellViewModel *viewModel = [[TCProfileFollowerFolloweeCellViewModel alloc] initWithUser:user];
    return viewModel;
}

- (TCProfileViewModel *) viewModelForUserProfileWithIndex: (NSUInteger) index {
    TCUser *user = [self.results objectAtIndex:index];
    TCProfileViewModel *viewModel = [[TCProfileViewModel alloc] initWithUser:user];
    return viewModel;
}

- (TCHashtagQuestionListViewModel *) viewModelForHashTagQuestionListWithIndex:(NSUInteger) index {
    TCHashtag *hashtag = [self.results objectAtIndex:index];
    TCHashtagQuestionListViewModel *viewModel = [[TCHashtagQuestionListViewModel alloc] initWithHashtag:hashtag];
    return viewModel;
}

@end
