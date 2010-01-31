//  Copyright 2010 Todd Ditchendorf
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "CRBaseViewController.h"
#import "CRTwitterPlugIn.h"
#import "CRTwitterUtils.h"
#import "CRTimelineViewController.h"
#import "CRThreadViewController.h"
#import "CRTweet.h"
#import "CRTweetListItem.h"

@implementation CRBaseViewController

- (id)initWithNibName:(NSString *)s bundle:(NSBundle *)b {
    if (self = [super initWithNibName:s bundle:b]) {
        [self setUpTwitterEngine];
    }
    return self;
}


- (void)dealloc {
    self.listView = nil;
    self.tweets = nil;
    self.twitterEngine = nil;
    [super dealloc];
}


#pragma mark -
#pragma mark Actions

- (IBAction)usernameButtonClicked:(id)sender {
    NSInteger i = [sender tag];
    [listView setSelectedItemIndex:i];
    NSString *username = [[tweets objectAtIndex:i] username];
    [self handleUsernameClicked:username];
}


- (IBAction)avatarButtonClicked:(id)sender {
    NSInteger i = [sender tag];
    //    [listView setSelectedItemIndex:i];
    NSString *username = [[tweets objectAtIndex:i] username];
    [self openUserPageInNewTabOrWindow:username];
}


#pragma mark -
#pragma mark TDListViewDataSource

- (NSUInteger)numberOfItemsInListView:(TDListView *)lv {
    NSAssert1(0, @"must implement %s", __PRETTY_FUNCTION__);
    return 0;
}


- (id)listView:(TDListView *)lv itemAtIndex:(NSUInteger)i {
    CRTweetListItem *item = [listView dequeueReusableItemWithIdentifier:[CRTweetListItem reuseIdentifier]];
    
    if (!item) {
        item = [[[CRTweetListItem alloc] init] autorelease];
        
        [item setTarget:self];
        [item setAction:@selector(tweetDoubleClicked:)];
        
        [item.avatarButton setTarget:self];
        [item.avatarButton setAction:@selector(avatarButtonClicked:)];
        
        [item.usernameButton setTarget:self];
        [item.usernameButton setAction:@selector(usernameButtonClicked:)];
        
        [item.textView setDelegate:self];
    }
    
    [item setSelected:i == [listView selectedItemIndex]];
    
    [item setTag:i];
    [item.avatarButton setTag:i];
    [item.usernameButton setTag:i];
    item.tweet = [tweets objectAtIndex:i];
    [item setNeedsDisplay:YES];
    
    return item;
}


#pragma mark -
#pragma mark TDListViewDelegate

- (CGFloat)listView:(TDListView *)lv extentForItemAtIndex:(NSUInteger)i {
    NSString *text = [[[tweets objectAtIndex:i] attributedText] string];
    CGFloat width = NSWidth([listView bounds]) - [CRTweetListItem horizontalTextMargins];
    
    CGFloat textHeight = 0;
    if (width > [CRTweetListItem minimumWidthForDrawingText]) {
        NSUInteger opts = NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingTruncatesLastVisibleLine;
        NSRect textRect = [text boundingRectWithSize:NSMakeSize(width, MAXFLOAT) options:opts attributes:[CRTweetListItem textAttributes]];
        textHeight = NSHeight(textRect) * [[[CRTweetListItem textAttributes] objectForKey:NSParagraphStyleAttributeName] lineHeightMultiple]; // for some reason lineHeightMultiplier is not factored in by default
    }
    CGFloat height = textHeight + [CRTweetListItem defaultHeight];
    
    CGFloat minHeight = [CRTweetListItem minimumHeight];
    height = (height < minHeight) ? minHeight : height;
    return height;
}


#pragma mark -
#pragma mark CRTextViewDelegate

- (void)textView:(CRTextView *)tv linkWasClicked:(NSURL *)URL {
    NSString *URLString = [URL absoluteString];
    
    NSString *username = nil;
    
    NSRange r = [URLString rangeOfString:@"twitter.com/"];
    if (NSNotFound != r.location) {
        username = [URLString substringFromIndex:r.location + r.length];
        r = [username rangeOfString:@"/"];
        if (NSNotFound != r.location) {
            username = [username substringToIndex:r.location];
        }
    }
    
    if ([username length] && ![[username lowercaseString] hasPrefix:@"search?"]) {
        [self handleUsernameClicked:username];
    } else {
        [self openURLInNewTabOrWindow:URLString];
    }
}


#pragma mark -
#pragma mark MGTwitterEngine

- (void)setUpTwitterEngine {
    self.twitterEngine = nil;
    
    NSString *username = [[CRTwitterPlugIn instance] selectedUsername];
    if (![username length]) {
        NSArray *usernames = [[CRTwitterPlugIn instance] usernames];
        if ([usernames count]) {
            username = [usernames objectAtIndex:0];
            [[CRTwitterPlugIn instance] setSelectedUsername:username];
        }
    }
    NSString *password = nil;
    if ([username length]) {
        password = [[CRTwitterPlugIn instance] passwordFor:username];
    }
    
    if (!username || !password) {
        return;
    }
    
    self.twitterEngine = [[[MGTwitterEngine alloc] initWithDelegate:self] autorelease];
    [twitterEngine setUsername:username password:password];
}


- (void)requestSucceeded:(NSString *)connectionIdentifier {
    //    NSLog(@"Request succeeded for connectionIdentifier = %@", connectionIdentifier);
}


- (void)requestFailed:(NSString *)connectionIdentifier withError:(NSError *)error {
    NSLog(@"Request failed for connectionIdentifier = %@, error = %@ (%@)", 
          connectionIdentifier, 
          [error localizedDescription], 
          [error userInfo]);
}


- (NSMutableArray *)tweetsFromStatuses:(NSArray *)inStatuses {
    //NSLog(@"Got statuses for %@:\r%@", requestID, inStatuses);
    //NSLog(@"Got statuses for %@:\r %d", requestID, [inStatuses count]);
    
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[inStatuses count]];
    
    NSString *myname = [[[CRTwitterPlugIn instance] selectedUsername] lowercaseString];
    NSString *atmyname = [NSString stringWithFormat:@"@%@", myname];
    NSString *defaultAvatarURLString = CRDefaultProfileImageURLString();
    
    for (NSDictionary *inStatus in inStatuses) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        NSDictionary *inUser = [inStatus objectForKey:@"user"];
        
        // id
        NSNumber *statusID = [inStatus objectForKey:@"id"];
        [d setObject:statusID forKey:@"id"];
        
        // date
        [d setObject:[inStatus objectForKey:@"created_at"] forKey:@"created_at"];
        
        // avatarURLString
        NSString *avatarURLString = [inUser objectForKey:@"profile_image_url"];
        if (![avatarURLString length])  {
            avatarURLString = defaultAvatarURLString;
        }
        
        [d setObject:avatarURLString forKey:@"avatarURLString"];
        
        // isMentionMe
        NSString *text = [inStatus objectForKey:@"text"];
        BOOL isMentionMe = [text rangeOfString:atmyname options:NSCaseInsensitiveSearch].length;
        [d setObject:[NSNumber numberWithBool:isMentionMe] forKey:@"isMentionMe"];
        
        // markup status
        NSArray *mentions = nil;
        NSAttributedString *attributedText = CRAttributedStatus(text, &mentions);
        if (![attributedText length]) {
            attributedText = CRDefaultAttributedStatus(text);
        }
        [d setObject:attributedText forKey:@"attributedText"];
        [d setObject:text forKey:@"text"];
        
        BOOL isReply = NO;
        NSNumber *inReplyToStatusID = [inStatus objectForKey:@"in_reply_to_status_id"];
        if (inReplyToStatusID) {
            isReply = YES;
            [d setObject:inReplyToStatusID forKey:@"inReplyToIdentifier"];
        }
        [d setObject:[NSNumber numberWithBool:isReply] forKey:@"isReply"];
        
        // name/username
        [d setObject:[inUser objectForKey:@"name"] forKey:@"name"];
        [d setObject:[inUser objectForKey:@"screen_name"] forKey:@"username"];
        
        BOOL writtenByMe = [[[d objectForKey:@"username"] lowercaseString] isEqualToString:myname];
        [d setObject:[NSNumber numberWithBool:writtenByMe] forKey:@"isByMe"];
        
        [result addObject:[CRTweet tweetFromDictionary:d]];
    }
    
    return result;
}


#pragma mark -
#pragma mark WebScripting Bridge

- (void)openUserPageInNewTabOrWindow:(NSString *)username {
    [self openURLInNewTabOrWindow:[NSString stringWithFormat:@"http://twitter.com/%@", username]];
}


- (void)openURLInNewTabOrWindow:(NSString *)URLString {
    BOOL inTab = [[CRTwitterPlugIn instance] tabbedBrowsingEnabled];
    [self openURLString:URLString inNewTab:inTab];
}


- (void)openURLString:(NSString *)URLString inNewTab:(BOOL)inTab {
    [self openURL:[NSURL URLWithString:URLString] inNewTab:inTab];
}


- (void)openURL:(NSURL *)URL inNewTab:(BOOL)inTab {
    NSEvent *evt = [NSApp currentEvent];
    
    BOOL shiftKeyWasPressed = [[CRTwitterPlugIn instance] wasShiftKeyPressed:[evt modifierFlags]];    
    BOOL inForeground = [[NSUserDefaults standardUserDefaults] boolForKey:kCRTwitterSelectNewTabsAndWindowsKey];
    if (shiftKeyWasPressed) {
        inForeground = !inForeground;
    }
    
    if (inTab) {
        [[CRTwitterPlugIn instance] openURL:URL inNewTabInForeground:inForeground];
    } else {
        [[CRTwitterPlugIn instance] openURL:URL inNewWindowInForeground:inForeground];
    }
}


- (void)pushTimelineFor:(NSString *)username {
    CRTimelineViewController *vc = [[[CRTimelineViewController alloc] initWithType:CRTimelineTypeUser] autorelease];
    vc.title = username;
    vc.displayedUsername = username;
    vc.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:vc animated:YES];
}


- (void)handleUsernameClicked:(NSString *)username {
    NSEvent *evt = [NSApp currentEvent];
    
    BOOL middleButtonClick = (2 == [evt buttonNumber]);
    BOOL commandKeyWasPressed = [[CRTwitterPlugIn instance] wasCommandKeyPressed:[evt modifierFlags]];
    BOOL cmdClick = (commandKeyWasPressed || middleButtonClick);
    
    if (cmdClick) {
        [self openUserPageInNewTabOrWindow:username];
    } else {
        [self pushTimelineFor:username];
    }    
}

@synthesize listView;
@synthesize tweets;
@synthesize twitterEngine;
@end
