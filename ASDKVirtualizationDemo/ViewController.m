//
//  ViewController.m
//  ASDKVirtualizationDemo
//
//  Created by Ethan Nagel on 7/8/15.
//  Copyright (c) 2015 Ethan Nagel. All rights reserved.
//

#import "ViewController.h"

#import <ASTableView.h>


static const int MIN_BUFFER = 10;
static const int MAX_BUFFER = 20;

static const int INITAL_SIZE = 20;

@interface ViewController () <ASTableViewDataSource, ASTableViewDelegate>

@property (weak, nonatomic) IBOutlet ASTableView *tableView;

@property (nonatomic) NSMutableArray *sections;

@end


@implementation ViewController {
  BOOL _requestingData;
}

#pragma mark - UIViewController overrides

- (void)viewDidLoad
{
  [super viewDidLoad];

  self.tableView.asyncDataSource = self;
  self.tableView.asyncDelegate  = self;
  self.tableView.automaticallyAdjustsContentOffset = YES;

  self.sections = [self initialData];

  _requestingData = YES;

  [self.tableView reloadDataWithCompletion:^{
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.sections[0] count]/2 inSection:0];
    [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionMiddle];

    dispatch_async(dispatch_get_main_queue(), ^{
      _requestingData = NO;
      [self visibleNodesChanged];
    });
  }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Data

static const NSTimeInterval ONE_DAY = 24 * 60 * 60;

-(NSArray *)generateDatesFrom:(NSDate *)startDate count:(NSInteger)count dir:(int)dir
{
  // excludes the startDate

  NSDate *date = startDate;
  NSMutableArray *dates = [[NSMutableArray alloc] init];

  if (dir==-1) {
    date = [date dateByAddingTimeInterval:-ONE_DAY * (count+1)];
  }

  for(int index=0; index<count; index++) {
    date = [date dateByAddingTimeInterval:ONE_DAY];
    [dates addObject:date];
  }

  return [dates copy];
}

- (NSMutableArray *)initialData
{
  NSMutableArray *rows = [[NSMutableArray alloc] init];

  // start a ways earlier than today...

  NSDate *today = [NSDate date];

  [rows addObjectsFromArray:[self generateDatesFrom:today count:INITAL_SIZE/2 dir:-1]];
  [rows addObject:today];
  [rows addObjectsFromArray:[self generateDatesFrom:today count:INITAL_SIZE/2 dir:1]];

  return [@[rows] mutableCopy];
}

- (void)beginFetchRowsBefore:(NSInteger)before after:(NSInteger)after
{
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

    [self.tableView beginUpdates];

    NSMutableArray *rows = self.sections[0];

    // do deletes first...

    if (before < 0 || after < 0) {
      NSMutableIndexSet *indexSet = [[NSMutableIndexSet alloc] init];

      if (before < 0) {
        [indexSet addIndexesInRange:NSMakeRange(0, -before)];
      }

      if (after < 0) {
        [indexSet addIndexesInRange:NSMakeRange(rows.count+after, -after)];
      }

      [rows removeObjectsAtIndexes:indexSet];

      NSMutableArray *indexPaths = [[NSMutableArray alloc] init];
      [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:idx inSection:0]];
      }];

      [self.tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
    }
    
    if (before > 0 || after > 0) {
      NSMutableArray *dates = [[NSMutableArray alloc] init];
      NSMutableIndexSet *indexSet = [[NSMutableIndexSet alloc] init];

      if (before > 0) {
        [indexSet addIndexesInRange:NSMakeRange(0, before)];
        [dates addObjectsFromArray:[self generateDatesFrom:rows.firstObject count:before dir:-1]];
      }

      if (after > 0) {
        [indexSet addIndexesInRange:NSMakeRange(dates.count + rows.count, after)];
        [dates addObjectsFromArray:[self generateDatesFrom:rows.lastObject count:after dir:+1]];
      }

      [rows insertObjects:dates atIndexes:indexSet];

      NSMutableArray *indexPaths = [[NSMutableArray alloc] init];
      [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:idx inSection:0]];
      }];

      [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
    }

    [self.tableView endUpdatesAnimated:NO completion:^(BOOL success) {
      NSLog(@"done with updates.");
      dispatch_async(dispatch_get_main_queue(), ^{
        _requestingData = NO;
        //      [self visibleNodesChanged];
      });
    }];
  });
}

-(NSString *)formatDate:(NSDate *)date
{
  static NSDateFormatter *formatter;

  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterLongStyle;
    formatter.timeStyle = NSDateFormatterNoStyle;
  });

  return [formatter stringFromDate:date];
}

#pragma mark - Virtualization

- (void)visibleNodesChanged
{
  if (_requestingData) {
    NSLog(@"ignoring visibleRangeChange - requestingData");
    return;
  }

  // called whenever the visible nodes changes

  NSArray *visibleRows = self.tableView.indexPathsForVisibleRows;

  NSInteger first = [visibleRows.firstObject row];
  NSInteger last = [visibleRows.lastObject row];

  NSInteger before = 0;
  NSInteger after = 0;

  NSMutableArray *rows = self.sections[0];

  if (first < MIN_BUFFER) {
    // grow range up...

    before = MAX_BUFFER - first;
  }

  NSInteger remaining = rows.count - last;

  if (remaining < MIN_BUFFER) {
    // grow range down...

    after = MAX_BUFFER - remaining;
  }
  
  if (before || after) {

    if (before == 0 && first > MAX_BUFFER) {
      before = MAX_BUFFER - first;
    } else if (after == 0 && remaining > MAX_BUFFER) {
      after = MAX_BUFFER - remaining;
    }

    _requestingData = YES;
    NSLog(@"fetching before:%ld after:%ld", before, after);
    [self beginFetchRowsBefore:before after:after];
  }
}

#pragma mark - ASTableViewDataSource/Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
  return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  NSMutableArray *rows = self.sections[section];

  return rows.count;
}

- (ASCellNode *)tableView:(ASTableView *)tableView nodeForRowAtIndexPath:(NSIndexPath *)indexPath
{
  NSMutableArray *rows = self.sections[indexPath.section];
  NSDate *date = rows[indexPath.row];

  ASTextCellNode *cellNode = [[ASTextCellNode alloc] init];
  cellNode.text = [self formatDate:date];

  NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
  NSDateComponents *comp = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:date];

  if (comp.day == 1) {
    cellNode.backgroundColor = [UIColor yellowColor];
  }

  return cellNode;
}

- (void)tableView:(ASTableView *)tableView willDisplayNodeForRowAtIndexPath:(NSIndexPath *)indexPath
{
  [self visibleNodesChanged]; // give virtualization an opportunity to begin adding data...
}

@end
