//
//  CKCalendarView.m
//  MBCalendarKit
//
//  Created by Moshe Berman on 4/10/13.
//  Copyright (c) 2013 Moshe Berman. All rights reserved.
//

@import QuartzCore;

#import "CKCalendarView.h"

//  Auxiliary Views
#import "CKCalendarHeaderView.h"
#import "CKCalendarHeaderViewDelegate.h"
#import "CKCalendarHeaderViewDataSource.h"
#import "CKCalendarCell.h"
#import "CKTableViewCell.h"
#import "CKCalendarAnimationWrapperView.h"

#import "NSCalendarCategories.h"
#import "NSDate+Description.h"
#import "UIView+AnimatedFrame.h"

@interface CKCalendarView () <CKCalendarHeaderViewDataSource, CKCalendarHeaderViewDelegate, UITableViewDataSource, UITableViewDelegate> {
    NSUInteger _firstWeekDay;
}

// MARK: - Cell Recycling

/**
 Cells that were enqueued after being cleared off of the screen.
 */
@property (nonatomic, strong) NSMutableArray <CKCalendarCell *> * spareCells;

/**
 Cells that are dequeued for display. Usually on the screen, but might not be if an animation is in progress.
 */
@property (nonatomic, strong) NSMutableArray <CKCalendarCell *> * usedCells;

// MARK: - Internal Views

/**
 The header view which shows the month and weekday names.
 */
@property (nonatomic, strong) CKCalendarHeaderView *headerView;


/**
 A wrapper that clips the cells and header so that cells animating in or out don't overflow the calendar view.
 */
@property (nonatomic, strong) CKCalendarAnimationWrapperView *wrapper;

/**
 A table view to show event details in.
 */
@property (nonatomic, strong) UITableView *table;

// MARK: - Calendar State

/**
 A cache for events that are being displayed.
 */
@property (nonatomic, strong) NSArray *events;

/**
 The index of the selected cell.
 */
@property (nonatomic, assign) NSUInteger selectedIndex;

/**
 The date that was last selected by the user, either by tapping on a cell or one of the arrows in the header.
 */
@property (nonatomic, strong) NSDate *previousDate;

/**
 Are the cells animating? Used to prevent animation races.
 */
@property (nonatomic, assign) BOOL isAnimating;

@end

@implementation CKCalendarView

// MARK: - Initializers

/**
 Initializes the calendar with a display mode.

 @param CalendarDisplayMode How much content to display: a month, a week, or a day?
 @return An instance of CKCalendarView.
 */
- (instancetype)initWithMode:(CKCalendarDisplayMode)CalendarDisplayMode
{
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _displayMode = CalendarDisplayMode;
        [self commonInitializer];
    }
    return self;
}


/**
 Calls `initWithMode:` with a mode of CKCalendarViewModeMonth.

 @param frame The frame. Doesn't matter because we drop this.
 @return An instance of CKCalendarView.
 */
- (instancetype)initWithFrame:(CGRect)frame
{
    self = [self initWithMode:CKCalendarViewModeMonth];
    if (self) {
        
    }
    return self;
}

/**
 Calls `initWithMode:` with a mode of CKCalendarViewModeMonth.
 
 @param coder An NSCoder. Doesn't matter because we drop this.
 @return An instance of CKCalendarView.
 */

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [self initWithMode:CKCalendarViewModeMonth];
    if (self) {
        
    }
    return self;
}

// MARK: - Common Initializer

/**
 This is code that gets run from every initializer.
 */
- (void)commonInitializer
{
    _locale = [NSLocale currentLocale];
    _calendar = [NSCalendar autoupdatingCurrentCalendar];
    [_calendar setLocale:_locale];
    _date = [NSDate date];
    
    NSDateComponents *components = [_calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:_date];
    _date = [_calendar dateFromComponents:components];
    
    _displayMode = CKCalendarViewModeMonth;
    _spareCells = [NSMutableArray new];
    _usedCells = [NSMutableArray new];
    _selectedIndex = [_calendar daysFromDate:[self _firstVisibleDateForDisplayMode:_displayMode] toDate:_date];
    _headerView = [CKCalendarHeaderView new];
    
    //  Accessory Table
    _table = [UITableView new];
    [_table setDelegate:self];
    [_table setDataSource:self];
    
    [_table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [_table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"noDataCell"];
    
    //  Events for selected date
    _events = [NSMutableArray new];
    
    //  Used for animation
    _previousDate = [NSDate date];
    _wrapper = [CKCalendarAnimationWrapperView new];
    _wrapper.clipsToBounds = YES;
    _isAnimating = NO;
    
    //  Date bounds
    _minimumDate = nil;
    _maximumDate = nil;
    
    //  First Weekday
    _firstWeekDay = [_calendar firstWeekday];
    
    [self _installHeader];
    [self _installWrapper];
    
}

// MARK: - View Lifecycle

- (void)willMoveToSuperview:(UIView *)newSuperview
{
    [super willMoveToSuperview:newSuperview];
}

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    
    [self _installTable];
    [self reloadAnimated:NO];
}

- (void)awakeFromNib
{
    
#if TARGET_INTERFACE_BUILDER
    [self invalidateIntrinsicContentSize];
    [self.superview setNeedsLayout];
#else 
    [self reloadAnimated:NO];
#endif
    
    [super awakeFromNib];
}

- (void)removeFromSuperview
{
    self.headerView.delegate = nil;
    self.headerView.dataSource = nil;
    
    [self.superview removeConstraints:self.table.constraints];
    [self.table removeFromSuperview];
    
    [super removeFromSuperview];
}

- (void)prepareForInterfaceBuilder
{
    [super prepareForInterfaceBuilder];
    
    [self reloadAnimated:NO];
}

// MARK: - Reload

- (void)reload
{
    [self reloadAnimated:NO];
}

- (void)reloadAnimated:(BOOL)animated
{
    /**
     *  Sort & cache the events for the current date.
     */
    
    if ([[self dataSource] respondsToSelector:@selector(calendarView:eventsForDate:)]) {
        NSArray *sortedArray = [[[self dataSource] calendarView:self eventsForDate:[self date]] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSDate *d1 = [obj1 date];
            NSDate *d2 = [obj2 date];
            
            return [d1 compare:d2];
        }];
        
        [self setEvents:sortedArray];
    }
    
    /**
     *  TODO: Possibly add a delegate method here, per issue #20.
     */
    
    /**
     *  Reload the calendar view.
     */
    
    [self _layoutCellsAnimated:animated];
    [self.headerView reloadData];
    [self.table reloadData];
}

// MARK: - Size

- (CGFloat)_heightForDisplayMode:(CKCalendarDisplayMode)displayMode
{
    CGFloat headerHeight = self.headerView.intrinsicContentSize.height;
    CGFloat columnCount = [self _columnCountForDisplayMode:self.displayMode];
    CGFloat rowCount = [self _rowCountForDisplayMode:self.displayMode];
    CGFloat cellSideLength = columnCount > 0 ? CGRectGetWidth(self.superview.bounds)/columnCount : 0.0;
    
    CGFloat height = headerHeight + (cellSideLength * rowCount);
    
    return height;
}

- (CGFloat)_cellRatio
{
    NSCalendar *calendar = self.calendar;
    
    CGFloat numberOfDaysPerWeek = [calendar daysPerWeek];
    CGFloat width = CGRectGetWidth(self.bounds);
    
    return width/numberOfDaysPerWeek;
}

// MARK: - Layout

- (void)updateConstraints
{
    [self _layoutCellsAnimated:NO];
    [super updateConstraints];
}

- (CGSize)intrinsicContentSize
{
    CGFloat width = UIViewNoIntrinsicMetric;
    
    if(self.superview)
    {
        width = CGRectGetWidth(self.superview.bounds);
    }
    
    CGFloat height = [self _heightForDisplayMode:self.displayMode];
    
    return CGSizeMake(width, height);
}

+ (BOOL)requiresConstraintBasedLayout
{
    return YES;
}

- (BOOL)translatesAutoresizingMaskIntoConstraints
{
    return NO;
}

- (UILayoutPriority)contentCompressionResistancePriorityForAxis:(UILayoutConstraintAxis)axis
{
    return UILayoutPriorityRequired;
}

- (UILayoutPriority)contentHuggingPriorityForAxis:(UILayoutConstraintAxis)axis
{
    if (axis == UILayoutConstraintAxisHorizontal)
    {
        return UILayoutPriorityDefaultLow;
    }
    else
    {
        return UILayoutPriorityRequired;
    }
}

// MARK: - Installing Internal Views

- (void)_installTable
{
    if (!self.superview)
    {
        return;
    }
    
    if (![self.table isDescendantOfView:self.superview])
    {
        /* Set up the table */
        [self.superview addSubview:self.table];
        [self.superview bringSubviewToFront:self];
        
        self.table.translatesAutoresizingMaskIntoConstraints = NO;
        
        NSLayoutConstraint *leading = [NSLayoutConstraint constraintWithItem:self.table
                                                                   attribute:NSLayoutAttributeLeading
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:self.superview
                                                                   attribute:NSLayoutAttributeLeading
                                                                  multiplier:1.0
                                                                    constant:0.0];
        
        NSLayoutConstraint *trailing = [NSLayoutConstraint constraintWithItem:self.table
                                                                    attribute:NSLayoutAttributeTrailing
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:self.superview
                                                                    attribute:NSLayoutAttributeTrailing
                                                                   multiplier:1.0
                                                                     constant:0.0];
        
        NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:self.table
                                                               attribute:NSLayoutAttributeTop
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:self
                                                               attribute:NSLayoutAttributeBottom
                                                              multiplier:1.0
                                                                constant:0.0];
        
        NSLayoutConstraint *bottom = [NSLayoutConstraint constraintWithItem:self.table
                                                                  attribute:NSLayoutAttributeBottom
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:self.superview
                                                                  attribute:NSLayoutAttributeBottom
                                                                 multiplier:1.0
                                                                   constant:0.0];
        
        [self.superview addConstraints:@[leading, trailing, top, bottom]];
    }
}

- (void)_installWrapper
{
    if(![self.wrapper isDescendantOfView:self])
    {
        [self addSubview:self.wrapper];
        self.wrapper.translatesAutoresizingMaskIntoConstraints = NO;
        
        NSLayoutConstraint *trailing = [NSLayoutConstraint constraintWithItem:self.wrapper
                                                                    attribute:NSLayoutAttributeTrailing
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:self
                                                                    attribute:NSLayoutAttributeTrailing
                                                                   multiplier:1.0
                                                                     constant:0.0];
        
        NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:self.wrapper
                                                               attribute:NSLayoutAttributeTop
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:self
                                                               attribute:NSLayoutAttributeTop
                                                              multiplier:1.0
                                                                constant:0.0];
        
        NSLayoutConstraint *bottom = [NSLayoutConstraint constraintWithItem:self.wrapper
                                                                  attribute:NSLayoutAttributeBottom
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:self
                                                                  attribute:NSLayoutAttributeBottom
                                                                 multiplier:1.0
                                                                   constant:0.0];
        
        NSLayoutConstraint *leading = [NSLayoutConstraint constraintWithItem:self.wrapper
                                                                   attribute:NSLayoutAttributeLeading
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:self
                                                                   attribute:NSLayoutAttributeLeading
                                                                  multiplier:1.0
                                                                    constant:0.0];
        
        
        [self addConstraints:@[trailing, top, bottom, leading]];
    }
}

- (void)_installHeader
{
    CKCalendarHeaderView *header = [self headerView];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [header setDelegate:self];
    [header setDataSource:self];
    
    if (![self.headerView isDescendantOfView:self.wrapper])
    {
        [self.wrapper addSubview:self.headerView];
        
        NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:self.headerView
                                                               attribute:NSLayoutAttributeTop
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:self.wrapper
                                                               attribute:NSLayoutAttributeTop
                                                              multiplier:1.0
                                                                constant:0.0];
        
        NSLayoutConstraint *leading = [NSLayoutConstraint constraintWithItem:self.headerView
                                                                   attribute:NSLayoutAttributeLeading
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:self.wrapper
                                                                   attribute:NSLayoutAttributeLeading
                                                                  multiplier:1.0
                                                                    constant:0.0];
        
        NSLayoutConstraint *trailing = [NSLayoutConstraint constraintWithItem:self.headerView
                                                                    attribute:NSLayoutAttributeTrailing
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:self.wrapper
                                                                    attribute:NSLayoutAttributeTrailing
                                                                   multiplier:1.0
                                                                     constant:0.0];
        
        [self.wrapper addConstraints:@[top, leading, trailing]];
    }
}

- (void)_installShadow
{
    [self.layer setShadowColor:[[UIColor darkGrayColor] CGColor]];
    [self.layer setShadowOffset:CGSizeMake(0, 3)];
    [self.layer setShadowOpacity:1.0];
}

// MARK: - Lay Out Cells


- (void)_layoutCellsAnimated:(BOOL)animated
{
    /*
     If we don't require a superview, the cell width computation will be wrong.
     Autolayout may complain, and bad things will happen. The warning is: 
     
     > Failed to rebuild layout engine without detectable loss of precision.  This should never happen.  Performance and correctness may suffer.
     
     There are very few Google/Stack Overflow results for this message, 
     but this answer (by a UIKit Engineer before he joined Apple) has a lot of good info: https://stackoverflow.com/a/27284071/224988
     */
    if ([self isAnimating] || !self.superview)
    {
        return;
    }
    
    [self setIsAnimating:YES];
    
    //  Count the rows and columns that we'll need
    NSUInteger rowCount = [self _rowCountForDisplayMode:[self displayMode]];
    NSUInteger columnCount = [self _columnCountForDisplayMode:[self displayMode]];
    
    
    /* Do some animation setup. */
    NSMutableArray <CKCalendarCell *> *cellsToRemoveAfterAnimation = self.usedCells.mutableCopy;
    NSMutableArray <CKCalendarCell *> *cellsBeingAnimatedIntoView = [NSMutableArray new];
    
    /* Calculate the pre-animation offset */
    
    CGFloat yOffset = 0;
    CGFloat cellRatio = [self _cellRatio];
    
    BOOL isDifferentMonth = ![[self calendar] date:[self date] isSameMonthAs:[self previousDate]];
    BOOL isNextMonth = isDifferentMonth && ([[self date] timeIntervalSinceDate:[self previousDate]] > 0);
    BOOL isPreviousMonth = isDifferentMonth && (!isNextMonth);
    
    // If the next month is about to be shown, we want to add the new cells at the bottom of the calendar
    if (isNextMonth) {
        yOffset = [self _heightForDisplayMode:[self displayMode]] - cellRatio;
    }
    
    //  If we're showing the previous month, add the cells at the top
    else if(isPreviousMonth)
    {
        yOffset = -([self _heightForDisplayMode:[self displayMode]]) + cellRatio;
    }
    
    else if ([[self calendar] date:[self previousDate] isSameDayAs:[self date]])
    {
        yOffset = 0;
    }
    
    //  Cache the start date & header offset
    NSDate *workingDate = [self _firstVisibleDateForDisplayMode:[self displayMode]];
    
    //  A working index...
    NSUInteger cellIndex = 0;
    
    // Pinning cells instead of manually positioning.
    UIView *verticalPinningView = self.headerView;
    UIView *horizontalPinningView = self.wrapper;
    
    NSLayoutAttribute horizontalPinningAttribute = NSLayoutAttributeLeading;
    
    for (NSUInteger row = 0; row < rowCount; row++) {
        
        horizontalPinningAttribute = NSLayoutAttributeLeading;
        horizontalPinningView = self.wrapper;
        
        for (NSUInteger column = 0; column < columnCount; column++) {
            
            /* STEP 1: create the cell */
            CKCalendarCell *cell = [self _dequeueCell];
            
            /* STEP 2:  We need to know some information about the cells - namely, if they're in
             the same month as the selected date and if any of them represent the system's
             value representing "today".
             */
            
            BOOL cellRepresentsToday = [[self calendar] date:workingDate isSameDayAs:[NSDate date]];
            BOOL isThisMonth = [[self calendar] date:workingDate isSameMonthAs:[self date]];
            BOOL isInRange = [self _dateIsBetweenMinimumAndMaximumDates:workingDate];
            isInRange = isInRange || [[self calendar] date:workingDate isSameDayAs:[self minimumDate]];
            isInRange = isInRange || [[self calendar] date:workingDate isSameDayAs:[self maximumDate]];
            
            /* STEP 3:  Here we style the cells accordingly.
             
             If the cell represents "today" then select it, and set
             the selectedIndex.
             
             If the cell is part of another month, gray it out.
             
             If the cell can't be selected, hide the number entirely.
             */
            
            if (cellRepresentsToday && isThisMonth && isInRange) {
                [cell setState:CKCalendarMonthCellStateTodayDeselected];
            }
            else if(!isInRange)
            {
                [cell setOutOfRange];
            }
            else if (!isThisMonth) {
                [cell setState:CKCalendarMonthCellStateInactive];
            }
            else
            {
                [cell setState:CKCalendarMonthCellStateNormal];
            }
            
            /* STEP 4: Show the day of the month in the cell. */
            
            NSUInteger day = [[self calendar] daysInDate:workingDate];
            [cell setNumber:@(day)];
            
            
            /* STEP 5: Show event dots */
            
            if([[self dataSource] respondsToSelector:@selector(calendarView:eventsForDate:)])
            {
                BOOL showDot = ([[[self dataSource] calendarView:self eventsForDate:workingDate] count] > 0);
                [cell setShowDot:showDot];
            }
            else
            {
                [cell setShowDot:NO];
            }
            
            /* STEP 6: Set the index */
            [cell setIndex:cellIndex];
            
            if (cellIndex == [self selectedIndex]) {
                [cell setSelected];
            }
            
            /* Step 7: Prepare the cell for animation */
            [cellsBeingAnimatedIntoView addObject:cell];
            
            /* STEP 8: Install the cell in the view hierarchy. */
            [self.wrapper addSubview:cell];
            
            /* STEP 9: Position the cell. */
            
            if (cell.topConstraint)
            {
                [cell removeConstraint:cell.topConstraint];
            }
            
            if (cell.leadingConstraint)
            {
                [cell removeConstraint:cell.leadingConstraint];
            }
            
            cell.topConstraint = [NSLayoutConstraint constraintWithItem:cell
                                                              attribute:NSLayoutAttributeTop
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:verticalPinningView
                                                              attribute:NSLayoutAttributeBottom
                                                             multiplier:1.0
                                                               constant:0.0];
            
            if(row == 0)
            {
                cell.topConstraint.constant = yOffset;
            }
            
            cell.leadingConstraint = [NSLayoutConstraint constraintWithItem:cell
                                                                  attribute:NSLayoutAttributeLeading
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:horizontalPinningView
                                                                  attribute:horizontalPinningAttribute
                                                                 multiplier:1.0
                                                                   constant:0.0];
            
            
            
            NSLayoutConstraint *width = [NSLayoutConstraint constraintWithItem:cell
                                                                     attribute:NSLayoutAttributeWidth
                                                                     relatedBy:NSLayoutRelationEqual
                                                                        toItem:self.wrapper
                                                                     attribute:NSLayoutAttributeWidth
                                                                    multiplier:1.0/columnCount
                                                                      constant:0.0];
            
            [self.wrapper addConstraints:@[width, cell.leadingConstraint, cell.topConstraint]];
            
            /* STEP 10: Update our pinning views and attributes for the following cell. */
            
            horizontalPinningView = cell;
            horizontalPinningAttribute = NSLayoutAttributeTrailing;
            
            if (column == columnCount - 1)
            {
                verticalPinningView = cell;
            }
            
            /* STEP 11: Move to the next date before we continue iterating. */
            workingDate = [[self calendar] dateByAddingDays:1 toDate:workingDate];
            cellIndex++;
        }
    }
    
    [self.wrapper bringSubviewToFront:self.headerView];
    
    /* Perform the animation */
    
    NSTimeInterval duration = 0.4;
    
    if (!animated)
    {
        duration = 0.0;
    }
    
    
    [self.superview layoutIfNeeded];
    [UIView
     animateWithDuration:duration
     animations:^{
         [self _moveCellsIntoView:cellsBeingAnimatedIntoView andCellsOutOfView:cellsToRemoveAfterAnimation usingOffset:yOffset];
         [self invalidateIntrinsicContentSize];
         [self.superview layoutIfNeeded];
     }
     completion:^(BOOL finished) {
         
         [self _cleanupCells:cellsToRemoveAfterAnimation];
         [cellsBeingAnimatedIntoView removeAllObjects];
         [self setIsAnimating:NO];
     }];
    
    
    
}

// MARK: - Cell Animation

- (void)_moveCellsIntoView:(NSMutableArray <CKCalendarCell *> *)cellsBeingAnimatedIntoView andCellsOutOfView:(NSMutableArray <CKCalendarCell *> *)cellsToRemoveAfterAnimation usingOffset:(CGFloat)yOffset
{
    for (CKCalendarCell *appearingCell in cellsBeingAnimatedIntoView)
    {
        appearingCell.topConstraint.constant = 0.0;
    }
    
    // Only animate the top row - the rest will follow.
    NSInteger numberOfAnimatedCells = 0;
    
    for (CKCalendarCell *disappearingCell in cellsToRemoveAfterAnimation)
    {
        if(numberOfAnimatedCells >= [self _columnCountForDisplayMode:self.displayMode])
        {
            return;
        }
        
        disappearingCell.topConstraint.constant = -yOffset;
        numberOfAnimatedCells++;
    }
}

- (void)_cleanupCells:(NSMutableArray <CKCalendarCell *> *)cellsToCleanup
{
    for (CKCalendarCell *cell in cellsToCleanup) {
        [self _moveCellFromUsedToSpare:cell];
        
        [self.wrapper removeConstraints:cell.constraints];
        
        [cell removeFromSuperview];
    }
    
    [cellsToCleanup removeAllObjects];
}

// MARK: - Cell Recycling

- (CKCalendarCell *)_dequeueCell
{
    CKCalendarCell *cell = [[self spareCells] firstObject];
    
    if (!cell)
    {
        cell = [[CKCalendarCell alloc] init];
        cell.translatesAutoresizingMaskIntoConstraints = NO;
        NSLayoutConstraint *ratio = [NSLayoutConstraint constraintWithItem:cell
                                                                 attribute:NSLayoutAttributeHeight
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:cell
                                                                 attribute:NSLayoutAttributeWidth
                                                                multiplier:1.0
                                                                  constant:0.0];
        [cell addConstraint:ratio];
    }
    
    [self _moveCellFromSpareToUsed:cell];
    
    [cell prepareForReuse];
    
    return cell;
}

- (void)_moveCellFromSpareToUsed:(CKCalendarCell *)cell
{
    //  Move the used cells to the appropriate set
    [[self usedCells] addObject:cell];
    
    if ([[self spareCells] containsObject:cell]) {
        [[self spareCells] removeObject:cell];
    }
}

- (void)_moveCellFromUsedToSpare:(CKCalendarCell *)cell
{
    //  Move the used cells to the appropriate set
    [[self spareCells] addObject:cell];
    
    if ([[self usedCells] containsObject:cell]) {
        [[self usedCells] removeObject:cell];
    }
}


// MARK: - Setters

// TODO: Consider observing the `NSCalendar` instance to catch these changes for animation instead of overriding all these methods.

- (void)setCalendar:(NSCalendar *)calendar
{
    [self setCalendar:calendar animated:NO];
}

- (void)setCalendar:(NSCalendar *)calendar animated:(BOOL)animated
{
    if (calendar == nil) {
        calendar = [NSCalendar currentCalendar];
    }
    
    _calendar = calendar;
    [_calendar setLocale:_locale];
    [_calendar setFirstWeekday:_firstWeekDay];
    
    [self reloadAnimated:animated];
}

- (void)setLocale:(NSLocale *)locale
{
    [self setLocale:locale animated:NO];
}

- (void)setLocale:(NSLocale *)locale animated:(BOOL)animated
{
    if (locale == nil) {
        locale = [NSLocale currentLocale];
    }
    
    _locale = locale;
    [[self calendar] setLocale:locale];
    
    [self reloadAnimated:animated];
}

- (NSTimeZone *)timeZone
{
    return self.calendar.timeZone;
}

- (void)setTimeZone:(NSTimeZone *)timeZone
{
    [self setTimeZone:timeZone animated:NO];
}

- (void)setTimeZone:(NSTimeZone *)timeZone animated:(BOOL)animated
{
    if (!timeZone)
    {
        timeZone = [NSTimeZone defaultTimeZone];
    }
    
    [[self calendar] setTimeZone:timeZone];
    
    [self reloadAnimated:animated];
}

- (void)setDisplayMode:(CKCalendarDisplayMode)displayMode
{
    [self setDisplayMode:displayMode animated:NO];
}

- (void)setDisplayMode:(CKCalendarDisplayMode)displayMode animated:(BOOL)animated
{
    _displayMode = displayMode;
    _previousDate = _date;
    
    //  Update the index, so that we don't lose selection between mode changes
    NSInteger newIndex = [[self calendar] daysFromDate:[self _firstVisibleDateForDisplayMode:displayMode] toDate:[self date]];
    [self setSelectedIndex:newIndex];
    
    [self reloadAnimated:animated];
}

- (void)setDate:(NSDate *)date
{
    [self setDate:date animated:NO];
}

- (void)setDate:(NSDate *)date animated:(BOOL)animated
{
    
    if (!date) {
        date = [NSDate date];
    }
    
    NSDateComponents *components = [self.calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    date = [self.calendar dateFromComponents:components];
    
    BOOL minimumIsBeforeMaximum = [self _minimumDateIsBeforeMaximumDate];
    
    if (minimumIsBeforeMaximum) {
        
        if ([self _dateIsBeforeMinimumDate:date]) {
            date = [self minimumDate];
        }
        else if([self _dateIsAfterMaximumDate:date])
        {
            date = [self maximumDate];
        }
    }
    
    if ([[self delegate] respondsToSelector:@selector(calendarView:willSelectDate:)]) {
        [[self delegate] calendarView:self willSelectDate:date];
    }
    
    _previousDate = _date;
    _date = date;
    
    if ([[self delegate] respondsToSelector:@selector(calendarView:didSelectDate:)]) {
        [[self delegate] calendarView:self didSelectDate:date];
    }
    
    if ([[self dataSource] respondsToSelector:@selector(calendarView:eventsForDate:)]) {
        [self setEvents:[[self dataSource] calendarView:self eventsForDate:date]];
        [[self table] reloadData];
    }
    
    //  Update the index
    NSDate *newFirstVisible = [self _firstVisibleDateForDisplayMode:[self displayMode]];
    NSUInteger index = [[self calendar] daysFromDate:newFirstVisible toDate:date];
    [self setSelectedIndex:index];
    
    [self reloadAnimated:animated];
}


- (void)setMinimumDate:(NSDate *)minimumDate
{
    [self setMinimumDate:minimumDate animated:NO];
}

- (void)setMinimumDate:(NSDate *)minimumDate animated:(BOOL)animated
{
    _minimumDate = minimumDate;
    [self setDate:[self date] animated:animated];
}

- (void)setMaximumDate:(NSDate *)maximumDate
{
    [self setMaximumDate:[self date] animated:NO];
}

- (void)setMaximumDate:(NSDate *)maximumDate animated:(BOOL)animated
{
    _maximumDate = maximumDate;
    [self setDate:[self date] animated:animated];
}

- (void)setDataSource:(id<CKCalendarViewDataSource>)dataSource
{
    _dataSource = dataSource;
    
    [self reloadAnimated:NO];
}

// MARK: - CKCalendarHeaderViewDataSource

- (NSString *)titleForHeader:(CKCalendarHeaderView *)header
{
    CKCalendarDisplayMode mode = [self displayMode];
    
    if(mode == CKCalendarViewModeMonth)
    {
        return [[self date] monthAndYearOnCalendar:[self calendar]];
    }
    
    else if (mode == CKCalendarViewModeWeek)
    {
        NSDate *firstVisibleDay = [self _firstVisibleDateForDisplayMode:mode];
        NSDate *lastVisibleDay = [self _lastVisibleDateForDisplayMode:mode];
        
        NSMutableString *result = [NSMutableString new];
        
        [result appendString:[firstVisibleDay monthAndYearOnCalendar:[self calendar]]];
        
        //  Show the day and year
        if (![[self calendar] date:firstVisibleDay isSameMonthAs:lastVisibleDay]) {
            result = [[firstVisibleDay monthAbbreviationAndYearOnCalendar:[self calendar]] mutableCopy];
            [result appendString:@" - "];
            [result appendString:[lastVisibleDay monthAbbreviationAndYearOnCalendar:[self calendar]]];
        }
        
        
        return result;
    }
    
    //Otherwise, return today's date as a string
    return [[self date] monthAndDayAndYearOnCalendar:[self calendar]];
}

- (NSUInteger)numberOfColumnsForHeader:(CKCalendarHeaderView *)header
{
    return [self _columnCountForDisplayMode:[self displayMode]];
}

- (NSString *)header:(CKCalendarHeaderView *)header titleForColumnAtIndex:(NSInteger)index
{
    NSDate *firstDate = [self _firstVisibleDateForDisplayMode:[self displayMode]];
    NSDate *columnToShow = [[self calendar] dateByAddingDays:index toDate:firstDate];
    
    return [columnToShow dayNameOnCalendar:[self calendar]];
}


- (BOOL)headerShouldHighlightTitle:(CKCalendarHeaderView *)header
{
    CKCalendarDisplayMode mode = [self displayMode];
    
    if (mode == CKCalendarViewModeDay) {
        return [[self calendar] date:[NSDate date] isSameDayAs:[self date]];
    }
    
    return NO;
}

- (BOOL)headerShouldDisableBackwardButton:(CKCalendarHeaderView *)header
{
    
    //  Never disable if there's no minimum date
    if (![self minimumDate]) {
        return NO;
    }
    
    CKCalendarDisplayMode mode = [self displayMode];
    
    if (mode == CKCalendarViewModeMonth)
    {
        return [[self calendar] date:[self date] isSameMonthAs:[self minimumDate]];
    }
    else if(mode == CKCalendarViewModeWeek)
    {
        return [[self calendar] date:[self date] isSameWeekAs:[self minimumDate]];
    }
    
    return [[self calendar] date:[self date] isSameDayAs:[self minimumDate]];
}

- (BOOL)headerShouldDisableForwardButton:(CKCalendarHeaderView *)header
{
    
    //  Never disable if there's no minimum date
    if (![self maximumDate]) {
        return NO;
    }
    
    CKCalendarDisplayMode mode = [self displayMode];
    
    if (mode == CKCalendarViewModeMonth)
    {
        return [[self calendar] date:[self date] isSameMonthAs:[self maximumDate]];
    }
    else if(mode == CKCalendarViewModeWeek)
    {
        return [[self calendar] date:[self date] isSameWeekAs:[self maximumDate]];
    }
    
    return [[self calendar] date:[self date] isSameDayAs:[self maximumDate]];
}

// MARK: - CKCalendarHeaderViewDelegate

- (void)forwardTapped
{
    NSDate *date = [self date];
    NSDate *today = [NSDate date];
    
    /* If the cells are animating, don't do anything or we'll break the view */
    
    if ([self isAnimating]) {
        return;
    }
    
    /*
     
     Moving forward or backwards for month mode
     should select the first day of the month,
     unless the newly visible month contains
     [NSDate date], in which case we want to
     highlight that day instead.
     
     */
    
    
    if ([self displayMode] == CKCalendarViewModeMonth) {
        
        NSUInteger maxDays = [[self calendar] daysPerMonthUsingReferenceDate:date];
        NSUInteger todayInMonth =[[self calendar] daysInDate:date];
        
        //  If we're the last day of the month, just roll over a day
        if (maxDays == todayInMonth) {
            date = [[self calendar] dateByAddingDays:1 toDate:date];
        }
        
        //  Otherwise, add a month and then go to the first of the month
        else{
            date = [[self calendar] dateByAddingMonths:1 toDate:date];              //  Add a month
            NSUInteger day = [[self calendar] daysInDate:date];                     //  Only then go to the first of the next month.
            date = [[self calendar] dateBySubtractingDays:day-1 fromDate:date];
        }
        
        //  If today is in the visible month, jump to today
        if([[self calendar] date:date isSameMonthAs:[NSDate date]]){
            NSUInteger distance = [[self calendar] daysFromDate:date toDate:today];
            date = [[self calendar] dateByAddingDays:distance toDate:date];
        }
    }
    
    /*
     
     For week mode, we move ahead by a week, then jump to
     the first day of the week. If the newly visible week
     contains today, we set today as the active date.
     
     */
    
    else if([self displayMode] == CKCalendarViewModeWeek)
    {
        
        date = [[self calendar] dateByAddingWeeks:1 toDate:date];                   //  Add a week
        
        NSUInteger dayOfWeek = [[self calendar] weekdayInDate:date];
        date = [[self calendar] dateBySubtractingDays:dayOfWeek-self.calendar.firstWeekday fromDate:date];   //  Jump to sunday
        
        //  If today is in the visible week, jump to today
        if ([[self calendar] date:date isSameWeekAs:today]) {
            NSUInteger distance = [[self calendar] daysFromDate:date toDate:today];
            date = [[self calendar] dateByAddingDays:distance toDate:date];
        }
        
    }
    
    /*
     
     In day mode, simply move ahead by one day.
     
     */
    
    else{
        date = [[self calendar] dateByAddingDays:1 toDate:date];
    }
    
    //apply the new date
    [self setDate:date animated:YES];
}

- (void)backwardTapped
{
    
    NSDate *date = [self date];
    NSDate *today = [NSDate date];
    
    /* If the cells are animating, don't do anything or we'll break the view */
    
    if ([self isAnimating]) {
        return;
    }
    
    /*
     
     Moving forward or backwards for month mode
     should select the first day of the month,
     unless the newly visible month contains
     [NSDate date], in which case we want to
     highlight that day instead.
     
     */
    
    if ([self displayMode] == CKCalendarViewModeMonth) {
        
        date = [[self calendar] dateBySubtractingMonths:1 fromDate:date];       //  Subtract a month
        NSUInteger day = [[self calendar] daysInDate:date];
        date = [[self calendar] dateBySubtractingDays:day-1 fromDate:date];     //  Go to the first of the month
        
        //  If today is in the visible month, jump to today
        if([[self calendar] date:date isSameMonthAs:[NSDate date]]){
            NSUInteger distance = [[self calendar] daysFromDate:date toDate:today];
            date = [[self calendar] dateByAddingDays:distance toDate:date];
        }
    }
    
    /*
     
     For week mode, we move backward by a week, then jump
     to the first day of the week. If the newly visible
     week contains today, we set today as the active date.
     
     */
    
    else if([self displayMode] == CKCalendarViewModeWeek)
    {
        date = [[self calendar] dateBySubtractingWeeks:1 fromDate:date];               //  Add a week
        
        NSUInteger dayOfWeek = [[self calendar] weekdayInDate:date];
        date = [[self calendar] dateBySubtractingDays:dayOfWeek-1 fromDate:date];   //  Jump to sunday
        
        //  If today is in the visible week, jump to today
        if ([[self calendar] date:date isSameWeekAs:today]) {
            NSUInteger distance = [[self calendar] daysFromDate:date toDate:today];
            date = [[self calendar] dateByAddingDays:distance toDate:date];
        }
        
    }
    
    /*
     
     In day mode, simply move backward by one day.
     
     */
    
    else{
        date = [[self calendar] dateBySubtractingDays:1 fromDate:date];
    }
    
    //apply the new date
    [self setDate:date animated:YES];
}

// MARK: - Rows and Columns

- (NSUInteger)_rowCountForDisplayMode:(CKCalendarDisplayMode)displayMode
{
    if (displayMode == CKCalendarViewModeWeek) {
        return 1;
    }
    else if(displayMode == CKCalendarViewModeMonth)
    {
        return [[self calendar] weeksPerMonthUsingReferenceDate:[self date]];
    }
    
    return 0;
}

- (NSUInteger)_columnCountForDisplayMode:(NSUInteger)displayMode
{
    if (displayMode == CKCalendarViewModeDay) {
        return 0;
    }
    
    NSUInteger columnCount = [[self calendar] daysPerWeekUsingReferenceDate:[self date]];
    
    if (columnCount == 0)
    {
        columnCount = 7.0; // Disallow 0, because we divide by this return value in several places.
    }
    
    return columnCount;
}

// MARK: - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger count = [[self events] count];
    
    if (count == 0) {
        count = 2;
    }
    
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSUInteger count = [[self events] count];
    
    if (count == 0) {
        UITableViewCell *cell = [[self table] dequeueReusableCellWithIdentifier:@"noDataCell"];
        [[cell textLabel] setTextAlignment:NSTextAlignmentCenter];
        [[cell textLabel] setTextColor:[UIColor colorWithWhite:0.2 alpha:0.8]];
        [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
        
        if ([indexPath row] == 1) {
            [[cell textLabel] setText:NSLocalizedString(@"No Events", @"A label for a table with no events.")];
        }
        else
        {
            [[cell textLabel] setText:@""];
        }
        return cell;
    }
    
    CKTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    
    CKCalendarEvent *event = [[self events] objectAtIndex:[indexPath row]];
    
    [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
    
    [[cell textLabel] setText:[event title]];
    
    UIView *colorView = [[UIView alloc] initWithFrame:CGRectMake(3, 6, 20, 20)];
    CALayer *layer = [CALayer layer];
    layer.backgroundColor = [[event color] CGColor];
    layer.frame = colorView.frame;
    [colorView.layer insertSublayer:layer atIndex:0];
    
    if(nil != event.image)
    {
        cell.imageView.image = [UIImage imageWithData:event.image];
    }
    else {
        cell.imageView.image = nil;
    }
    
    [cell addSubview:colorView];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    if ([[self events] count] == 0) {
        return;
    }
    
    if ([[self delegate] respondsToSelector:@selector(calendarView:didSelectEvent:)]) {
        [[self delegate] calendarView:self didSelectEvent:[self events][[indexPath row]]];
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

// MARK: - First Weekday

- (void)setFirstWeekDay:(NSUInteger)firstWeekDay
{
    _firstWeekDay = firstWeekDay;
    self.calendar.firstWeekday = firstWeekDay;
    
    [self reload];
}

- (NSUInteger)firstWeekDay
{
    return _firstWeekDay;
}

// MARK: - Date Calculations

- (NSDate *)firstVisibleDate
{
    return [self _firstVisibleDateForDisplayMode:[self displayMode]];
}

- (NSDate *)_firstVisibleDateForDisplayMode:(CKCalendarDisplayMode)displayMode
{
    // for the day mode, just return today
    if (displayMode == CKCalendarViewModeDay) {
        return [self date];
    }
    else if(displayMode == CKCalendarViewModeWeek)
    {
        return [[self calendar] firstDayOfTheWeekUsingReferenceDate:[self date] andStartDay:self.calendar.firstWeekday];
    }
    else if(displayMode == CKCalendarViewModeMonth)
    {
        NSDate *firstOfTheMonth = [[self calendar] firstDayOfTheMonthUsingReferenceDate:[self date]];
        
        NSDate *firstVisible = [[self calendar] firstDayOfTheWeekUsingReferenceDate:firstOfTheMonth andStartDay:self.calendar.firstWeekday];
        
        return firstVisible;
    }
    
    return [self date];
}

- (NSDate *)lastVisibleDate
{
    return [self _lastVisibleDateForDisplayMode:[self displayMode]];
}

- (NSDate *)_lastVisibleDateForDisplayMode:(CKCalendarDisplayMode)displayMode
{
    // for the day mode, just return today
    if (displayMode == CKCalendarViewModeDay) {
        return [self date];
    }
    else if(displayMode == CKCalendarViewModeWeek)
    {
        return [[self calendar] lastDayOfTheWeekUsingReferenceDate:[self date]];
    }
    else if(displayMode == CKCalendarViewModeMonth)
    {
        NSDate *lastOfTheMonth = [[self calendar] lastDayOfTheMonthUsingReferenceDate:[self date]];
        return [[self calendar] lastDayOfTheWeekUsingReferenceDate:lastOfTheMonth];
    }
    
    return [self date];
}

- (NSUInteger)_numberOfVisibleDaysforDisplayMode:(CKCalendarDisplayMode)displayMode
{
    //  If we're showing one day, well, we only one
    if (displayMode == CKCalendarViewModeDay) {
        return 1;
    }
    
    //  If we're showing a week, count the days per week
    else if (displayMode == CKCalendarViewModeWeek)
    {
        return [[self calendar] daysPerWeek];
    }
    
    //  If we're showing a month, we need to account for the
    //  days that complete the first and last week of the month
    else if (displayMode == CKCalendarViewModeMonth)
    {
        
        NSDate *firstVisible = [self _firstVisibleDateForDisplayMode:CKCalendarViewModeMonth];
        NSDate *lastVisible = [self _lastVisibleDateForDisplayMode:CKCalendarViewModeMonth];
        return [[self calendar] daysFromDate:firstVisible toDate:lastVisible];
    }
    
    //  Default to 1;
    return 1;
}

// MARK: - Minimum and Maximum Dates

- (BOOL)_minimumDateIsBeforeMaximumDate
{
    //  If either isn't set, return YES
    if (![self _hasNonNilMinimumAndMaximumDates]) {
        return YES;
    }
    
    return [[self calendar] date:[self minimumDate] isBeforeDate:[self maximumDate]];
}

- (BOOL)_hasNonNilMinimumAndMaximumDates
{
    return [self minimumDate] != nil && [self maximumDate] != nil;
}

- (BOOL)_dateIsBeforeMinimumDate:(NSDate *)date
{
    return [[self calendar] date:date isBeforeDate:[self minimumDate]];
}

- (BOOL)_dateIsAfterMaximumDate:(NSDate *)date
{
    return [[self calendar] date:date isAfterDate:[self maximumDate]];
}

- (BOOL)_dateIsBetweenMinimumAndMaximumDates:(NSDate *)date
{
    //  If there are both the minimum and maximum dates are unset,
    //  behave as if all dates are in range.
    if (![self minimumDate] && ![self maximumDate]) {
        return YES;
    }
    
    //  If there's no minimum, treat all dates that are before
    //  the maximum as valid
    else if(![self minimumDate])
    {
        return [[self calendar]date:date isBeforeDate:[self maximumDate]];
    }
    
    //  If there's no maximum, treat all dates that are before
    //  the minimum as valid
    else if(![self maximumDate])
    {
        return [[self calendar] date:date isAfterDate:[self minimumDate]];
    }
    
    return [[self calendar] date:date isAfterDate:[self minimumDate]] && [[self calendar] date:date isBeforeDate:[self maximumDate]];
}

// MARK: - Dates & Indices

- (NSInteger)_indexFromDate:(NSDate *)date
{
    NSDate *firstVisible = [self firstVisibleDate];
    return [[self calendar] daysFromDate:firstVisible toDate:date];
}

- (NSDate *)_dateFromIndex:(NSInteger)index
{
    NSDate *firstVisible = [self firstVisibleDate];
    return [[self calendar] dateByAddingDays:index toDate:firstVisible];
}

// MARK: - Touch Handling

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    UITouch *t = [touches anyObject];
    
    CGPoint p = [t locationInView:self];
    
    [self pointInside:p withEvent:event];
    [super touchesMoved:touches withEvent:event];
}


- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    
    NSDate *firstDate = [self _firstVisibleDateForDisplayMode:[self displayMode]];
    NSDate *dateToSelect = [[self calendar] dateByAddingDays:[self selectedIndex] toDate:firstDate];
    
    BOOL animated = ![[self calendar] date:[self date] isSameMonthAs:dateToSelect];
    
    [self setDate:dateToSelect animated:animated];
    
    [super touchesEnded:touches withEvent:event];
}

/**
 If a touch was cancelled, reset the index.
 */
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    NSDate *firstDate = [self _firstVisibleDateForDisplayMode:[self displayMode]];
    
    NSUInteger index = [[self calendar] daysFromDate:firstDate toDate:[self date]];
    
    [self setSelectedIndex:index];
    
    NSDate *dateToSelect = [[self calendar] dateByAddingDays:[self selectedIndex] toDate:firstDate];
    [self setDate:dateToSelect animated:NO];
    
    
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    CGRect bounds = [self bounds];
    bounds.origin.y += [self headerView].frame.size.height;
    bounds.size.height -= [self headerView].frame.size.height;
    
    if(CGRectContainsPoint(self.wrapper.bounds, point)){
        /* Highlight and select the appropriate cell */
        
        NSUInteger index = [self selectedIndex];
        
        //  Get the index from the cell we're in
        for (CKCalendarCell *cell in [self usedCells]) {
            CGRect rect = [cell frame];
            if (CGRectContainsPoint(rect, point)) {
                index = [cell index];
                break;
            }
            
        }
        
        //  Clip the index to minimum and maximum dates
        NSDate *date = [self _dateFromIndex:index];
        
        if ([self _dateIsAfterMaximumDate:date]) {
            index = [self _indexFromDate:[self maximumDate]];
        }
        else if([self _dateIsBeforeMinimumDate:date])
        {
            index = [self _indexFromDate:[self minimumDate]];
        }
        
        // Save the new index
        [self setSelectedIndex:index];
        
        //  Update the cell highlighting
        for (CKCalendarCell *cell in [self usedCells]) {
            if ([cell index] == [self selectedIndex]) {
                [cell setSelected];
            }
            else
            {
                [cell setDeselected];
            }
            
        }
    }
    
    return [super pointInside:point withEvent:event];
}

@end
