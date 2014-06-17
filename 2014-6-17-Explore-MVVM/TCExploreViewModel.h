//
//  TCExploreViewModel.h
//  Three Cents
//
//  Created by Bob Spryn on 4/6/14.
//  Copyright (c) 2014 Three Cents, Inc. All rights reserved.
//

#import "RVMViewModel.h"
@class TCProfileFollowerFolloweeCellViewModel;
@class TCProfileViewModel;
@class TCHashtagQuestionListViewModel;

NS_ENUM(NSUInteger, TCExploreTab) {
    TCExploreTabHashtags,
    TCExploreTabUsers
};

NS_ENUM(NSUInteger, TCExploreSearchCellState) {
    TCExploreSearchCellStateNone,
    TCExploreSearchCellStateReady,
    TCExploreSearchCellStateSearching,
    TCExploreSearchCellStateNoResults
};

@interface TCExploreViewModel : RVMViewModel

/** An enum to track what tab is currently visible
 * **Default**: TCExploreTabHashtags
 */
@property (nonatomic, assign) enum TCExploreTab tab;

/** The results to display in the table view.
 */
@property (nonatomic, strong, readonly) NSOrderedSet *results;

/** An enum that represents the current state of the search cell
 * **Default**: TCExploreSearchCellStateNone
 */
@property (nonatomic, assign, readonly) enum TCExploreSearchCellState searchCellState;

/** The value of the search string currently entered in the searchbar */
@property (nonatomic, copy) NSString *searchString;

/** A signal that sends `NSError` values when errors occur */
@property (nonatomic, strong, readonly) RACSignal *exploreErrorSignal;

/** The text to be shown in the search/loading cell */
@property (nonatomic, copy, readonly) NSString *searchLoadingCellText;

/** A bool controlling whether or not we should load popular results */
@property (nonatomic, assign, readonly) BOOL wantsToLoadPopularResults;

/** A RACCommand that triggers the loading of popular results */
@property (nonatomic, strong, readonly) RACCommand *loadPopularResults;

/** A signal that sends a value whenever the table needs to reload */
@property (nonatomic, strong, readonly) RACSignal *tableUpdateSignal;

@property (nonatomic, strong, readonly) RACCommand *searchCommand;

/** Provides a view model for a follower/followee cell
 @param index an NSUInteger of the cell/user in question
 @return an appropriately configured TCProfileFollowerFolloweeCellViewModel
 */
- (TCProfileFollowerFolloweeCellViewModel *) viewModelForUserCellWithIndex:(NSUInteger) index;

/** Provides a view model for a full profile view
 @param index an NSUInteger of the cell/user for which the view model is being requested
 @return an appropriately configured TCProfileViewModel
 */
- (TCProfileViewModel *) viewModelForUserProfileWithIndex: (NSUInteger) index;

/** Provides a view model for a hashtag question list view controller
 @param index an NSUInteger of the cell/hashtag in question
 @return an appropriately configured TCHashtagQuestionListViewModel
 */
- (TCHashtagQuestionListViewModel *) viewModelForHashTagQuestionListWithIndex:(NSUInteger) index;

@end
