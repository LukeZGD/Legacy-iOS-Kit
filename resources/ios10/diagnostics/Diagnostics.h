#import <Foundation/Foundation.h>
#ifndef LIK_DIR
#define LIK_DIR @"/usr/local/share/lik-ios10"
#endif
#ifndef LIK_EXPORT_DIR
#define LIK_EXPORT_DIR @"/var/mobile/Media/Downloads/Legacy-iOS-Kit/Logs"
#endif
#define LIK_APP @"/Applications/LIKTools.app"
#ifndef LIK_SOCKET
#define LIK_SOCKET "/var/run/lik-ios10-diagnostics.sock"
#endif
#define LIK_SSH_PLIST @"/Library/LaunchDaemons/org.legacyioskit.ios10.transport.plist"
NSDictionary *LIKSnapshot(void);
NSDictionary *LIKRequest(NSString *command);
NSDictionary *LIKRun(NSString *path, NSArray *arguments);
BOOL LIKSSHListening(void);
NSString *LIKReadTail(NSString *path);
NSString *LIKPhase(void);

NSDictionary *LIKRunTimed(NSString *path, NSArray *arguments, NSTimeInterval timeout);
NSDictionary *LIKRunLogged(NSString *path, NSArray *arguments, NSTimeInterval timeout, NSString *logPath);
NSDictionary *LIKSSHAction(NSString *action);
NSDictionary *LIKSSHLastResult(void);
NSString *LIKExportReport(NSString *report, NSError **error);

NSString *LIKReadExportLog(NSString *path);
