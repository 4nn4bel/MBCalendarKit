MBCalendarKit
================
MBCalendarKit is a calendar control written in UIKit. I've found existing implementations to be inadequate and difficult to work with, so I rolled my own.

Screenshots:
------------

![Month](./screens/month.png "Month View")
![Week](./screens/week.png "Week View")
![Delegate](./screens/day.png "Day View")

Getting Started:
---------------

You'll need to set up the dependencies, described below. Alternatively, MBCalendarKit is now a registered CocoaPod. I don't use CocoaPods, but I did run a quick test on using the following line in my Podfile:

`pod 'MBCalendarKit', '~>2.2.2'`

If there are any problems, please head over to issue #48 and leave a comment.


Dependencies:
-------------

You'll need the iOS 7 SDK. I haven't tested it against versions of iOS prior to 6.0. Your mileage may vary. (I'm pretty sure I used some NSCalendarUnit values that aren't defined before iOS 5. You'll also have to look at the table view cell implementation in `CKCalendarView.m`.) 


As of MBCalendarKit 2.0.0, the project uses the LLVM compiler's modules feature. 

MBCalendarKit requires Quartz, Core Graphics, UIKit, and Foundation. The Unit Tests build against the XCTest framework. Xcode should take care of all those except `QuartzCore.framework`. If you're building the tests, you may have to link to XCTest yourself, as well.


Relevant Files:
---------------

Aside from the framework dependencies described above, you'll want everything in the CalendarKit folder.

Showing a Calendar
--------------------------------------

You have two choices for showing a calendar using MBCalendarKit. 

1. You can show an instance of `CKCalendarView`. Use this if you want to manually manage your view hierarchy or have a finer control over your calendar view.


```` objective-c

/*
Here's how you'd show a CKCalendarView from within a view controller. 
It's just four easy steps.
*/
		
// 0. In either case, import CalendarKit:
#import "CalendarKit/CalendarKit.h"
    	
// 1. Instantiate a CKCalendarView
CKCalendarView *calendar = [CKCalendarView new];
 		
// 2. Optionally, set up the datasource and delegates
[calendar setDelegate:self];
[calendar setDataSource:self];
 		
// 3. Present the calendar 
[[self view] addSubview:calendar];
		
````


2. Your second option is to create an instance of `CKCalendarViewController`. Using a CKCalendarViewController gives you the added benefit of a "today" button and a segmented control in the toolbar, which allows you to select the display mode. Note that `CKCalendarViewController` subclasses `UINavigationViewController`, so it can't be installed inside of another navigation controller. 


```` objective-c

/* 
Here's how you'd show a CKCalendarViewController from 
within a view controller. It's just four easy steps.
*/
		
// 0. In either case, import CalendarKit:
#import "CalendarKit/CalendarKit.h"
    	
// 1. Instantiate a CKCalendarViewController
CKCalendarViewController *calendar = [CKCalendarViewController new];
 		
// 2. Optionally, set up the datasource and delegates
[calendar setDelegate:self];
[calendar setDataSource:self];
 		
// 3. Present the calendar 
[[self presentViewController:calendar animated:YES completion:nil];
		
````

---

**Note: From this point on, both the CKCalendarView class and the CKCalendarViewController classes are interchangeably referred to as the "calendar view", because they have common datasource and delegate APIs.** 

---



Showing Events
-------------------------

The `CKCalendarDataSource` protocol defines the following method, which supplies an array of `CKCalendarEvent` objects. The calendar view automatically shows an indicator in cells that represent dates that have events. 

```` objective-c
- (NSArray *)calendarView:(CKCalendarView *)calendarView eventsForDate:(NSDate *)date;
````
In your data source, implement this method and return the events matching the date being passed in. You may find some of the `NSCalendar+DateComparison` categories to be helpful here.

You can read more about the `CKCalendarEvent` clas below.
		
Handling User Interaction
-------------------------

These methods, defined in the `CKCalendarViewDelegate` protocol, are called on the delegate when the used selects a date. A date is considered selected when either an arrow in the header is tapped, or when the user lifts their finger from a cell.

```` objective-c
- (void)calendarView:(CKCalendarView *)calendarView willSelectDate:(NSDate *)date;
- (void)calendarView:(CKCalendarView *)calendarView didSelectDate:(NSDate *)date;
````  

This method is called on the delegate when a row is selected in the events table. You can use to push a detail view, for example.

```` objective-c
- (void)calendarView:(CKCalendarView *)CalendarView didSelectEvent:(CKCalendarEvent *)event;
````   
    
Calendar Events
----------------
`CKCalendarEvent` is a simple data structure class which holds a title, a date, and an info dictionary. The calendar view will display automatically display `CKCalendarEvent` objects as passed to it by its data sourcee. If you have custom information that you want to show in a detail view, you can attach it to the event's `info` property. 

As of MBCalendarKit 2.1.0, there's a `color` property as well. Setting it will cause the cell to display a colored "tag" in the cell. This feature should be considered experimental for now.

Day of the Week:
---
Version 2.2.0 adds support for the `firstWeekday` property of NSCalendar. If the `currentCalendar` (or whichever you set) has some day other than Sunday set as the first day of the week, the calendar view will respect that.

License:
========

MBCalendarKit is hereby released under the MIT License. See [LICENSE](/LICENSE) for details.


Thanks:
-------
Dave DeLong, for being an invaluable reference.

Various contributors for patches and reporting issues.

If you like this...
---
If you like MBCalendarKit, check out some of my other projects:

- [MBPlacePickerController](https://github.com/MosheBerman/MBPlacePickerController), a one stop shop for all of your CoreLocation needs, including a fallback UI for offline location setup.
- [MBTileParser](https://github.com/MosheBerman/MBTileParser), a cocos-2d compatible game engine written in UIKit.
- [MBTimelineViewController](https://github.com/MosheBerman/MBTimelineViewController), a scrolling timeline based on UICollectionView.
- [MBMenuController](https://github.com/MosheBerman/MBMenuController), a UIActionSheet clone with some nice effects.