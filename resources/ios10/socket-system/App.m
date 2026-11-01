#import <UIKit/UIKit.h>
#import "Diagnostics.h"
#import "SocketCore.h"
#import <unistd.h>
#import <sys/stat.h>
#import <signal.h>

@interface LIKController : UIViewController
@property(nonatomic,strong) UITextView *text;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIProgressView *progress;
@property(nonatomic,strong) NSMutableString *history;
@property(nonatomic,strong) NSArray *buttons;
@property(nonatomic,strong) NSString *logPath;
@property(nonatomic,strong) NSDictionary *lastReport;
@property(nonatomic,strong) NSString *lastState;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) BOOL requesting;
@property(nonatomic) UIBackgroundTaskIdentifier backgroundTask;
@end
@implementation LIKController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Socket (Kit)";self.view.backgroundColor=UIColor.whiteColor;self.history=[NSMutableString string];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(socketMessage:) name:@"SocketStatus" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(socketProgress:) name:@"SocketProgress" object:nil];
    self.logPath=@"/var/mobile/Library/Logs/LIK-iOS10/diagnostics.log";
    [[NSFileManager defaultManager] createDirectoryAtPath:self.logPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *previous=[NSString stringWithContentsOfFile:self.logPath encoding:NSUTF8StringEncoding error:nil];
    if(previous)[self.history appendString:previous.length>500000 ? [previous substringFromIndex:previous.length-500000] : previous];
    self.status=[UILabel new];self.status.numberOfLines=0;self.status.font=[UIFont systemFontOfSize:14];self.status.text=@"Checking the on-device installer…";
    self.progress=[UIProgressView new];self.progress.accessibilityLabel=@"Completed installation steps";
    self.text=[UITextView new];self.text.editable=NO;self.text.font=[UIFont fontWithName:@"Menlo" size:11];self.text.accessibilityLabel=@"Installation and diagnostic log";
    NSMutableArray *buttons=[NSMutableArray array];NSArray *titles=@[@"Install / Continue",@"Reboot and Verify",@"Run checks",@"Reinstall SSH",@"Fix SSH",@"Restart SSH",@"Export Logs",@"Copy Report",@"Share Report"];
    for(NSUInteger i=0;i<titles.count;i++){UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:titles[i] forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:13];b.tag=i;[b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];[buttons addObject:b];}
    self.buttons=buttons;
    NSMutableArray *views=[NSMutableArray arrayWithArray:@[self.status,self.progress]];
    for(NSArray *row in @[@[buttons[0],buttons[1]],@[buttons[2],buttons[6]],@[buttons[3],buttons[4],buttons[5]],@[buttons[7],buttons[8]]]) {
        UIStackView *v=[[UIStackView alloc] initWithArrangedSubviews:row];v.distribution=UIStackViewDistributionFillEqually;[v.heightAnchor constraintEqualToConstant:38].active=YES;[views addObject:v];
    }
    [views addObject:self.text];UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:views];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=6;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:stack];[NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:10],[stack.bottomAnchor constraintEqualToAnchor:self.bottomLayoutGuide.topAnchor constant:-6],[stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],[stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10]]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"About" style:UIBarButtonItemStylePlain target:self action:@selector(about)];
    [self append:@"App opened. Installation, SSH management and reboot verification run on this phone. No computer-driven installation is needed after jump-start."];
}
- (void)socketMessage:(NSNotification *)n {dispatch_async(dispatch_get_main_queue(),^{[self append:n.userInfo[@"message"]];});}
- (void)socketProgress:(NSNotification *)n {dispatch_async(dispatch_get_main_queue(),^{self.status.text=n.userInfo[@"message"];self.progress.progress=[n.userInfo[@"completed_steps"] floatValue]/5.0f;[self append:self.status.text];});}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];[self perform:@"status" quiet:NO export:NO];
    [self.timer invalidate];self.timer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(poll) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.timer invalidate];self.timer=nil;}
- (void)poll{if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive && !self.requesting)[self perform:@"status" quiet:YES export:NO];}
- (void)append:(NSString *)message {
    [self.history appendFormat:@"\n[%@]\n%@\n",NSDate.date,message];
    if(self.history.length>1000000)[self.history deleteCharactersInRange:NSMakeRange(0,self.history.length-1000000)];
    [self.history writeToFile:self.logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if(geteuid()==0){chown(self.logPath.fileSystemRepresentation,501,501);chmod(self.logPath.fileSystemRepresentation,0644);}
    self.text.text=self.history;[self.text scrollRangeToVisible:NSMakeRange(self.text.text.length,0)];
}
- (NSString *)reportText {
    NSData *json=[NSJSONSerialization dataWithJSONObject:self.lastReport ?: @{} options:NSJSONWritingPrettyPrinted error:nil];
    return [self.history stringByAppendingFormat:@"\nLATEST REPORT\n%@\n",[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"Report unavailable"];
}
- (void)perform:(NSString *)action quiet:(BOOL)quiet export:(BOOL)export {
    if(self.requesting)return;self.requesting=YES;
    for(UIButton *b in self.buttons)if(b.tag<7)b.enabled=NO;
    if(!quiet)[self append:[NSString stringWithFormat:@"Starting %@…",action]];
    UIApplication.sharedApplication.idleTimerDisabled=YES;
    self.backgroundTask=[UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{
        [self append:@"iOS is suspending the app. Reopen it; an interrupted package operation will not be blindly repeated."];
        if(self.backgroundTask!=UIBackgroundTaskInvalid){[UIApplication.sharedApplication endBackgroundTask:self.backgroundTask];self.backgroundTask=UIBackgroundTaskInvalid;}
    }];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{@autoreleasepool{
        NSDictionary *local=LIKSnapshot(),*helper=LIKRequest(action);
        NSDictionary *report=@{@"app_build":@"ios10-dev.10",@"app_checks":local,@"installer":helper};
        dispatch_async(dispatch_get_main_queue(),^{
            self.lastReport=report;NSDictionary *workflow=helper[@"workflow"] ?: @{};
            NSString *state=workflow[@"state"] ?: @"not-started";
            NSString *message=workflow[@"message"] ?: helper[@"error"] ?: @"Ready. Tap Install / Continue after jump-start.";
            NSDictionary *ssh=helper[@"ssh_action"] ?: helper[@"ssh_check"] ?: @{};
            NSString *sshState=[ssh[@"authentication_test"][@"authenticated"] boolValue]?@"SSH authentication verified":@"SSH not verified";
            self.status.text=[NSString stringWithFormat:@"%@\n%@",message,sshState];
            self.progress.progress=[workflow[@"completed_steps"] floatValue]/5.0f;
            if(!quiet || ![state isEqual:self.lastState]) {
                [self append:self.status.text];
                if(helper[@"error"])[self append:[@"ERROR: " stringByAppendingString:helper[@"error"]]];
                if(ssh[@"error"])[self append:[@"SSH: " stringByAppendingString:ssh[@"error"]]];
                if(!quiet && !export) {
                    NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
                    [self append:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"Could not format report"];
                }
            }
            self.lastState=state;self.requesting=NO;UIApplication.sharedApplication.idleTimerDisabled=NO;
            if(self.backgroundTask!=UIBackgroundTaskInvalid){[UIApplication.sharedApplication endBackgroundTask:self.backgroundTask];self.backgroundTask=UIBackgroundTaskInvalid;}
            for(UIButton *b in self.buttons)b.enabled=YES;
            BOOL running=[workflow[@"worker_running"] boolValue];
            ((UIButton *)self.buttons[0]).enabled=!running && ![state isEqual:@"complete"] && ![state isEqual:@"reboot-required"] && ![state isEqual:@"awaiting-ordinary-boot"];
            ((UIButton *)self.buttons[1]).enabled=[state isEqual:@"reboot-required"] || [state isEqual:@"awaiting-ordinary-boot"];
            for(NSUInteger i=3;i<=5;i++)((UIButton *)self.buttons[i]).enabled=!running;
            if(export){NSError *error=nil;NSString *path=LIKExportReport([self reportText],&error);[self append:path?[@"Exported through normal AFC: " stringByAppendingString:path]:[@"Export failed: " stringByAppendingString:error.localizedDescription ?: @"Unknown error"]];}
        });
    }});
}
- (void)tapped:(UIButton *)sender {
    if(sender.tag==2){[self perform:@"checks" quiet:NO export:NO];return;}
    if(sender.tag==6){[self perform:@"export-logs" quiet:NO export:YES];return;}
    if(sender.tag==7){UIPasteboard.generalPasteboard.string=[self reportText];[self append:@"Report copied."];return;}
    if(sender.tag==8){UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[[self reportText]] applicationActivities:nil];share.popoverPresentationController.sourceView=sender;share.popoverPresentationController.sourceRect=sender.bounds;[self presentViewController:share animated:YES completion:nil];return;}
    NSDictionary *actions=@{@0:@"install",@1:@"reboot-and-verify",@3:@"reinstall-ssh",@4:@"fix-ssh",@5:@"restart-ssh"};
    NSDictionary *messages=@{@0:@"Install the jailbreak assets, Zebra and Procyon on this phone. Keep this app open and the phone powered on until installation finishes.",@1:@"Reboot normally to verify the untether, then reopen this app. No DFU boot is needed for this test.",@3:@"Reinstall and reconfigure all bundled SSH files, start SSH automatically, and check authentication.",@4:@"Repair missing or damaged SSH files and configuration, restart SSH, and check authentication.",@5:@"Restart SSH and check authentication. Files and configuration will not be reinstalled or repaired."};
    NSString *action=actions[@(sender.tag)];if(!action)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:sender.currentTitle message:messages[@(sender.tag)] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:sender.currentTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self perform:action quiet:NO export:NO];}]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)about {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Socket (Kit) — dev.10" message:@"Installs and verifies the jailbreak locally after jump-start. Modified Socket 1.3 by staturnzz, adapted for this kit's temporary boot. Installs Socket's bootstrap, Zebra and Procyon locally. No boot-started helper or startup-cache modification is used. Built on Legacy iOS Kit and p0insettia; original authors and licenses are credited in the kit. This experimental build still needs hardware validation. Export Logs saves reports to Downloads/Legacy-iOS-Kit/Logs through normal AFC." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
@end
@interface LIKDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation LIKDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:[LIKController new]];[self.window makeKeyAndVisible];return YES;
}
@end
int main(int argc,char **argv){@autoreleasepool{signal(SIGPIPE,SIG_IGN);if(argc==2&&!strcmp(argv[1],"--socket-bootstrap"))return SocketInstallBootstrap();if(argc==2&&!strcmp(argv[1],"--socket-configure-untether"))return SocketConfigureUntether();return UIApplicationMain(argc,argv,nil,NSStringFromClass(LIKDelegate.class));}}
