//
//  TCExploreViewController.h
//  Three Cents
//
//  Created by Bob Spryn on 2/19/14.
//  Copyright (c) 2014 Three Cents, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
@class TCExploreViewModel;

@interface TCExploreViewController : UIViewController
/**
 * TCExploreViewController expects a view model
 */
@property (nonatomic, strong) TCExploreViewModel *viewModel;

@end
