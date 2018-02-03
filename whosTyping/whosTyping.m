//
//  whosTyping.m
//  whosTyping
//
//  Created by Wolfgang Baird on 1/21/18.
//  Copyright © 2018 Wolfgang Baird. All rights reserved.
//

@import AppKit;

#import <objc/runtime.h>

#import "IMHandle.h"
#import "IMPerson.h"
#import "IMAccount.h"
#import "IMAccountController.h"
#import "IMService-IMService_GetService.h"

#ifdef DEBUG
#    define DLog(...) NSLog(__VA_ARGS__)
#else
#    define DLog(...) /* */
#endif

@interface typeStatus : NSObject
+ (instancetype)sharedInstance;
@end

typeStatus *plugin;
NSBundle *bundle;
NSStatusItem *statusItem;
NSUserDefaults *userDefaults;
NSUInteger typingIndicators = 0;

NSTimer *_timer;
NSArray *gif;
NSUInteger gifFrame = 0;

typedef NS_ENUM(NSUInteger, WBTS_StatusBarType) {
    WBTS_StatusBarTypeTyping,
    WBTS_StatusBarTypeRead,
    WBTS_StatusBarTypeEmpty
};

static NSString *const kWBTS_PreferencesSuiteName = @"org.w0lf.typeStatus13";
static NSString *const kWBTS_PreferencesAnimatedKey = @"Animated";
static NSString *const kWBTS_PreferencesDurationKey = @"OverlayDuration";

@implementation typeStatus

+ (instancetype)sharedInstance {
    static typeStatus *plugin = nil;
    @synchronized(self) {
        if (!plugin) {
            plugin = [[self alloc] init];
        }
    }
    return plugin;
}

+ (void)load {
    plugin = [typeStatus sharedInstance];
    NSUInteger osx_ver = [[NSProcessInfo processInfo] operatingSystemVersion].minorVersion;
    NSLog(@"typeStatus : %@ loaded into %@ on macOS 10.%ld", [self class], [[NSBundle mainBundle] bundleIdentifier], (long)osx_ver);
    bundle = [NSBundle bundleWithIdentifier:kWBTS_PreferencesSuiteName];
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kWBTS_PreferencesSuiteName];
    [userDefaults registerDefaults:@{
                                     kWBTS_PreferencesDurationKey: @5.0,
                                     kWBTS_PreferencesAnimatedKey: @NO
                                     }];
}

- (NSString *)WBTS_NameForHandle:(NSString *)address {
    IMAccount *account = [[IMAccount alloc] initWithService:[IMService iMessageService]];
    IMHandle *handle = [account imHandleWithID:address];
    return handle._displayNameWithAbbreviation ?: address;
}

- (void)startSIanimation {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error;
        NSString *gifPath = [bundle pathForResource:@"iMTyping" ofType:@"gif"];
        NSData *gifData = [NSData dataWithContentsOfFile:gifPath options:NSDataReadingUncached error:&error];
        NSMutableArray *frames = nil;
        CGImageSourceRef src = CGImageSourceCreateWithData((CFDataRef)gifData, NULL);
        if (src) {
            size_t l = CGImageSourceGetCount(src);
            frames = [NSMutableArray arrayWithCapacity:l];
            for (size_t i = 0; i < l; i++) {
                CGImageRef img = CGImageSourceCreateImageAtIndex(src, i, NULL);
                if (img) {
                    NSImage *newFrame = [[NSImage alloc] initWithCGImage:img size:CGSizeMake(22, 22)];
                    [frames addObject:newFrame];
                    
//                    NSString *savePath = [NSString stringWithFormat:@"/Users/w0lf/Downloads/gif/%zu.png", i];
//                    NSData *imageData = [newFrame TIFFRepresentation];
//                    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
//                    NSDictionary *imageProps = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:1.0] forKey:NSImageCompressionFactor];
//                    imageData = [imageRep representationUsingType:NSJPEGFileType properties:imageProps];
//                    [imageData writeToFile:savePath atomically:NO];
                    
                    CGImageRelease(img);
                }
            }
            CFRelease(src);
        }
        gif = [frames copy];
    });
    
    if (!_timer) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                  target:self
                                                selector:@selector(timerCalled:)
                                                userInfo:nil
                                                 repeats:YES];
    }
}

- (void)stopSIanimation {
    if ([_timer isValid])
        [_timer invalidate];
    _timer = nil;
    statusItem.image = nil;
}

-(void)timerCalled:(NSTimer*)timer {
    gifFrame += 1;
    if (gifFrame >= gif.count)
        gifFrame = 0;
    statusItem.image = gif[gifFrame];
}

- (void)WBTS_SetStatus:(WBTS_StatusBarType)type :(NSString *)handle {
    static NSImage *TypingIcon;
    static NSImage *ReadIcon;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        TypingIcon = [bundle imageForResource:@"Typing.tiff"];
        [TypingIcon setTemplate:YES];
        TypingIcon.size = CGSizeMake(22.f, 22.f);
        
        ReadIcon = [bundle imageForResource:@"Read.tiff"];
        [ReadIcon setTemplate:YES];
        ReadIcon.size = CGSizeMake(22.f, 22.f);
    });
    
    if (type == WBTS_StatusBarTypeEmpty) {
        statusItem.length = 0;
        [self stopSIanimation];
        statusItem.title = nil;
        statusItem.attributedTitle = nil;
        return;
    }
    
    if (type == WBTS_StatusBarTypeRead)
        statusItem.image = ReadIcon;
    
    if (type == WBTS_StatusBarTypeTyping) {
        if ([userDefaults boolForKey:kWBTS_PreferencesAnimatedKey])
            [self startSIanimation];
        else
            statusItem.image = TypingIcon;
    }
    
    statusItem.title = [plugin WBTS_NameForHandle:handle];
    statusItem.length = -1;
}

@end

ZKSwizzleInterface(WBTS_SOTypingIndicatorView, SOTypingIndicatorView, NSView)
@implementation WBTS_SOTypingIndicatorView

- (void)destroyTypingLayer {
    DLog(@"typeStatus : destroyTypingLayer");
    
    if (self.superview == NSClassFromString(@"MaskedView"))
        typingIndicators--;
    
    if (typingIndicators == 0)
        [plugin WBTS_SetStatus:WBTS_StatusBarTypeEmpty :nil];
    
    ZKOrig(void);
}

- (void)createTypingLayer {
    DLog(@"typeStatus : createTypingLayer");
   
    if (self.superview == NSClassFromString(@"MaskedView"))
        typingIndicators++;
    
    ZKOrig(void);
}

- (void)startPulseAnimation {
    DLog(@"typeStatus : startPulseAnimation");
    ZKOrig(void);
}

@end

ZKSwizzleInterface(WBTS_IMTypingChatItem, IMTypingChatItem, NSObject)
@implementation WBTS_IMTypingChatItem

- (id)_initWithItem:(id)arg1 {
    NSString *address = [arg1 valueForKey:@"_handle"];
    [plugin WBTS_SetStatus:WBTS_StatusBarTypeTyping :address];
    return ZKOrig(id, arg1);
}

@end

@interface IMDMessageStore : NSObject
+ (id)sharedInstance;
- (id)messageWithGUID:(id)arg1;
@end

ZKSwizzleInterface(WBTS_IMDServiceSession, IMDServiceSession, NSObject)
@implementation WBTS_IMDServiceSession

+ (id)sharedInstance {
    return ZKOrig(id);
}

- (id)messageWithGUID:(id)arg1 {
    return ZKOrig(id, arg1);
}

- (void)didReceiveMessageReadReceiptForMessageID:(NSString *)messageID date:(NSDate *)date completionBlock:(id)completion {
    ZKOrig(void, messageID, date, completion);
    Class IMDMS = NSClassFromString(@"IMDMessageStore");
    [plugin WBTS_SetStatus:WBTS_StatusBarTypeRead :[[[IMDMS sharedInstance] messageWithGUID:messageID] valueForKey:@"handle"]];
//    HBTSPostMessage(HBTSMessageTypeReadReceipt, [[%c(IMDMessageStore) sharedInstance] messageWithGUID:messageID].handle, NO);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([userDefaults doubleForKey:kWBTS_PreferencesDurationKey] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [plugin WBTS_SetStatus:WBTS_StatusBarTypeEmpty :nil];
    });
}

@end

//ZKSwizzleInterface(WBTS_IMMessage, IMMessage, NSObject)
//@implementation WBTS_IMMessage
//
//- (void)_updateTimeRead:(id)arg1 {
//    ZKOrig(void, arg1);
//    DLog(@"typeStatus : _updateTimeRead");
//}
//
//@end

