#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <sys/types.h>
#import <unistd.h>
#import <fcntl.h>
#import <stdio.h>
#import "ProbeKit.h"

#define CS_OPS_STATUS 0
extern int csops(pid_t pid, uint32_t ops, void *useraddr, size_t usersize);

static NSString *gLogPath;

static void AppendRaw(const char *path, const char *text) {
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    write(fd, text, strlen(text));
    close(fd);
}

__attribute__((constructor)) static void ProbeBootConstructor(void) {
    char buf[256];
    int n = snprintf(buf, sizeof(buf), "ctor pid=%d uid=%d\n", getpid(), getuid());
    AppendRaw("/var/tmp/tsltv-probe-boot.log", buf);
}

static void AppendLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *message = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    NSString *line = [NSString stringWithFormat:@"%@ pid=%d %@\n",
                      [formatter stringFromDate:[NSDate date]], getpid(), message];
    NSLog(@"[TSLTVProbe] %@", message);
    AppendRaw("/var/tmp/tsltv-probe.log", [line UTF8String]);

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [gLogPath stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    if (![fm fileExistsAtPath:gLogPath]) {
        [@"" writeToFile:gLogPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
    if (!fh) {
        // Sandboxed (non no-sandbox) runs may not be able to create Documents/probe.log;
        // fall back to NSTemporaryDirectory() which is always writable inside the container.
        NSString *tmpLog = [NSTemporaryDirectory() stringByAppendingPathComponent:@"probe.log"];
        [fm createDirectoryAtPath:[tmpLog stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:NULL];
        if (![fm fileExistsAtPath:tmpLog]) {
            [@"" writeToFile:tmpLog atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
        fh = [NSFileHandle fileHandleForWritingAtPath:tmpLog];
    }
    if (!fh) return;
    @try {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh synchronizeFile];
    } @catch (NSException *exception) {
        NSLog(@"[TSLTVProbe] log write failed: %@", exception);
    } @finally {
        [fh closeFile];
    }
}

@interface ProbeViewController : UIViewController
@end

@implementation ProbeViewController {
    BOOL _loggedFirstFrame;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.15 blue:0.35 alpha:1.0];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = @"TSLTV PROBE\nDEMO RUNNING";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont boldSystemFontOfSize:64.0];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    AppendLog(@"stage=view_did_appear");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AppendLog(@"stage=first_frame");
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!_loggedFirstFrame) {
        _loggedFirstFrame = YES;
        AppendLog(@"stage=layout_complete bounds=%@", NSStringFromCGRect(self.view.bounds));
    }
}
@end

@interface ProbeSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ProbeSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    AppendLog(@"stage=scene_connect");
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[ProbeViewController alloc] init];
    [self.window makeKeyAndVisible];
}

@end

@interface ProbeAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ProbeAppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    AppendLog(@"stage=did_finish_launching state=%ld", (long)application.applicationState);
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[ProbeViewController alloc] init];
    [self.window makeKeyAndVisible];

    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:8787/"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSURLSessionDataTask *task = [[NSURLSession sharedSession]
            dataTaskWithURL:url
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            AppendLog(@"stage=http_8787 status=%ld bytes=%lu error=%@",
                      (long)status, (unsigned long)data.length,
                      error ? error.localizedDescription : @"none");
        }];
        [task resume];
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AppendLog(@"stage=heartbeat_2s");
    });
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    AppendLog(@"stage=did_become_active");
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        gLogPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/probe.log"];
        AppendLog(@"stage=main home=%@ args=%d", NSHomeDirectory(), argc);

        uint32_t flags = 0;
        int rc = csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags));
        AppendLog(@"stage=csops rc=%d flags=0x%x", rc, flags);

        NSString *probe = ProbeKitProbe();
        AppendLog(@"stage=framework_ok result=%@", probe);

        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([ProbeAppDelegate class]));
    }
}