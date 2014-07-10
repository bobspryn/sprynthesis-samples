//
//  TCFeedSearchLoadingCell.m
//  Three Cents
//
//  Created by Bob Spryn on 2/18/14.
//  Copyright (c) 2014 Three Cents, Inc. All rights reserved.
//

#import "TCExploreSearchLoadingCell.h"
#import "TCExploreViewModel.h"

@interface TCExploreSearchLoadingCell ()
@property (nonatomic, strong) UILabel *primaryLabel;
@property (nonatomic, strong) UIImageView *searchImageView;
@property (nonatomic, strong) CALayer *bottomBorder;
@end

@implementation TCExploreSearchLoadingCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.primaryLabel = [[UILabel alloc] init];
        self.primaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.primaryLabel.font = [UIFont fontWithDescriptor:[UIFontDescriptor preferredAvenirNextFontDescriptorWithTextStyle:UIFontTextStyleSubheadline] size:0];
        self.searchImageView = [[UIImageView alloc] initWithImageNamed:@"explore-search-icon"];
        self.searchImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.primaryLabel];
        [self.contentView addSubview:self.searchImageView];

        
        RACSignal *cellstateSignal = [RACObserve(self, viewModel.searchCellState) distinctUntilChanged];
        RAC(self.primaryLabel, textColor) = [cellstateSignal
            map:^id(NSNumber *cellState) {
                switch (cellState.integerValue) {
                    case TCExploreSearchCellStateReady:
                        return mTCOrangeDarkerColor;
                    case TCExploreSearchCellStateSearching:
                        return mTCDarkText;
                    default:
                        return mTCLightText;
                }
            }];
        
        RAC(self.searchImageView, hidden) = [[cellstateSignal
            map:^id(NSNumber *state) {
                return @(state.integerValue == TCExploreSearchCellStateReady);
            }] not];
        
        RAC(self, selectionStyle) = [cellstateSignal
            map:^id(NSNumber *state) {
                return state.integerValue == TCExploreSearchCellStateReady ? @(UITableViewCellSelectionStyleBlue) : @(UITableViewCellSelectionStyleNone);
            }];
        
        RAC(self.primaryLabel, text) = RACObserve(self, viewModel.searchLoadingCellText);
        
        self.backgroundColor = mTCDefaultCellBackgroundColor;
        self.bottomBorder = [CALayer layer];
        self.bottomBorder.backgroundColor = mTCDefaultBorderColor.CGColor;
        [self.layer addSublayer:self.bottomBorder];
    
    }
    return self;
}

- (void) updateConstraints {
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-8-[_primaryLabel]-[_searchImageView(20.5)]-16-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_primaryLabel, _searchImageView)]];
    [self.primaryLabel pinToSuperviewEdges:(JRTViewPinTopEdge|JRTViewPinBottomEdge) inset:0];
    [self.searchImageView centerInContainerOnAxis:NSLayoutAttributeCenterY];
    [super updateConstraints];
}

- (void) layoutSubviews {
    [super layoutSubviews];
    self.bottomBorder.frame = CGRectMake(0, self.frame.size.height - 0.5, self.frame.size.width, 0.5);
}

@end
