#import <Foundation/Foundation.h>
NSString *SocketBundleFile(NSString *name);
NSString *SocketEnsureRoot(void);
NSString *SocketPrepareRuntime(void);
NSDictionary *SocketAction(NSString *action);
int SocketInstallBootstrap(void);
int SocketConfigureUntether(void);
void status(const char *message);
