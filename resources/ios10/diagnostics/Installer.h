#import <Foundation/Foundation.h>
NSString *LIKJournal(void);
NSString *LIKPrepareJournal(void);
NSString *LIKBootIdentity(void);
NSString *LIKNextInstallStep(NSString *phase);
NSDictionary *LIKWorkflow(void);
BOOL LIKInstallationBusy(void);
NSDictionary *LIKStartInstall(void);
NSDictionary *LIKStartReboot(void);
int LIKInstallWorker(void);
int LIKRebootWorker(void);
void LIKVerifyOrdinaryBoot(void);
NSDictionary *LIKInstallerLogs(void);

BOOL LIKOrdinaryBootReady(NSDictionary *workflow, NSString *boot, NSDictionary *snapshot, BOOL springboard);
