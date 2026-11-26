#import "ProbeKit.h"
#import <unistd.h>

NSString *ProbeKitProbe(void) {
    return [NSString stringWithFormat:@"probe-kit-v1-pid-%d", getpid()];
}