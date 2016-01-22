    //
//  SEBViewController.m
//
//  Created by Daniel R. Schneider on 10/09/15.
//  Copyright (c) 2010-2016 Daniel R. Schneider, ETH Zurich,
//  Educational Development and Technology (LET),
//  based on the original idea of Safe Exam Browser
//  by Stefan Schneider, University of Giessen
//  Project concept: Thomas Piendl, Daniel R. Schneider, 
//  Dirk Bauer, Kai Reuter, Tobias Halbherr, Karsten Burger, Marco Lehre, 
//  Brigitte Schmucki, Oliver Rahs. French localization: Nicolas Dunand
//
//  ``The contents of this file are subject to the Mozilla Public License
//  Version 1.1 (the "License"); you may not use this file except in
//  compliance with the License. You may obtain a copy of the License at
//  http://www.mozilla.org/MPL/
//
//  Software distributed under the License is distributed on an "AS IS"
//  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
//  License for the specific language governing rights and limitations
//  under the License.
//
//  The Original Code is Safe Exam Browser for Mac OS X.
//
//  The Initial Developer of the Original Code is Daniel R. Schneider.
//  Portions created by Daniel R. Schneider are Copyright
//  (c) 2010-2016 Daniel R. Schneider, ETH Zurich, Educational Development
//  and Technology (LET), based on the original idea of Safe Exam Browser
//  by Stefan Schneider, University of Giessen. All Rights Reserved.
//
//  Contributor(s): ______________________________________.
//

#import <WebKit/WebKit.h>
#import "Constants.h"
#import "RNCryptor.h"

#import "SEBViewController.h"

@interface SEBViewController () <WKNavigationDelegate>
{
    NSURL *currentConfigPath;
    UIBarButtonItem *leftButton;
    
    @private
    NSInteger attempts;
}

@property (weak) IBOutlet UIView *containerView;
@property (copy) NSURLRequest *request;

@end

static NSMutableSet *browserWindowControllers;

@implementation SEBViewController

+ (WKWebViewConfiguration *)defaultWebViewConfiguration
{
    static WKWebViewConfiguration *configuration;
    
    if (!configuration) {
        configuration = [[WKWebViewConfiguration alloc] init];
    }
    
    return configuration;
}



- (void)viewDidLoad
{
    [super viewDidLoad];
    
    AppDelegate *appDelegate = [[UIApplication sharedApplication] delegate];
    appDelegate.sebViewController = self;
    
    _browserTabViewController = self.childViewControllers[0];
    _browserTabViewController.sebViewController = self;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(guidedAccessChanged)
                                                 name:UIAccessibilityGuidedAccessStatusDidChangeNotification object:nil];
    
    // Was SEB opened by loading a .seb file/using a seb:// link?
    if (appDelegate.sebFileURL) {
        // Yes: Load the .seb file now that the necessary SEB main view controller was loaded
        [self downloadAndOpenSEBConfigFromURL:appDelegate.sebFileURL];
    }
}


- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self startAutonomousSingleAppMode];
}


- (BOOL) prefersStatusBarHidden
{
    return YES;
}


#pragma mark - Button Handlers
-(void)leftDrawerButtonPress:(id)sender{
    [self.mm_drawerController toggleDrawerSide:MMDrawerSideLeft animated:YES completion:nil];
}

- (IBAction)goBack:(id)sender {
    [_browserTabViewController goBack];
}

- (IBAction)goForward:(id)sender {
    [_browserTabViewController goForward];
}

- (IBAction)reload:(id)sender {
    [_browserTabViewController reload];
}


// Called when the Guided Access status changes
- (void) guidedAccessChanged
{
    if (_finishedStartingUp && _guidedAccessActive && _ASAMActive == false) {
        // Is the exam already running?
        if (_examRunning) {
            
            // Exam running: Check if Guided Access is switched off
            if (UIAccessibilityIsGuidedAccessEnabled() == false) {
                
                /// Guided Access is off
                
                // Dismiss the Guided Access warning alert if it still was visible
                if (_guidedAccessWarningDisplayed) {
                    [_alertController dismissViewControllerAnimated:NO completion:nil];
                    _alertController = nil;
                    _guidedAccessWarningDisplayed = false;
                }
                
                // If there wasn't a lockdown covering view openend yet, initialize it
                if (!_sebLocked) {
                    
                    if (!_lockedViewController) {
                        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
                        _lockedViewController = [storyboard instantiateViewControllerWithIdentifier:@"SEBLockedView"];
                        _lockedViewController.controllerDelegate = self;
                    }
                    
                    if (!_lockedViewController.resignActiveLogString) {
                        _lockedViewController.resignActiveLogString = [[NSAttributedString alloc] initWithString:@""];
                    }
                    // Save current time for information about when Guided Access was switched off
                    _didResignActiveTime = [NSDate date];
                    DDLogError(@"Guided Accesss switched off!");
                    
                    // Open the lockdown view
                    [_lockedViewController willMoveToParentViewController:self];
                    
                    UIViewController *rootViewController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
                    
                    [rootViewController.view addSubview:_lockedViewController.view];
                    [rootViewController addChildViewController:_lockedViewController];
                    [_lockedViewController didMoveToParentViewController:self];
                    
                    _sebLocked = true;
                    
                    // Add log string for resign active
                    [_lockedViewController appendErrorString:[NSString stringWithFormat:@"%@\n", NSLocalizedString(@"Guided Access switched off!", nil)] withTime:_didResignActiveTime];
                }
            } else {
                
                /// Guided Access is on again
                
                // Add log string
                _didBecomeActiveTime = [NSDate date];
                
                [_alertController dismissViewControllerAnimated:NO completion:nil];
                _alertController = nil;

                [_lockedViewController appendErrorString:[NSString stringWithFormat:@"%@\n", NSLocalizedString(@"Guided Access is switched on again.", nil)] withTime:_didBecomeActiveTime];
                
                // Close unlock windows only if the correct quit/restart password was entered already
                if (_unlockPasswordEntered) {
                    _unlockPasswordEntered = false;
//                    [_alertController dismissViewControllerAnimated:NO completion:nil];
//                    _alertController = nil;
                    [_lockedViewController shouldCloseLockdownWindows];
                }
            }
        } else {
            
            /// Exam is not yet running
            
            // If Guided Access switched on
            if (UIAccessibilityIsGuidedAccessEnabled() == true) {
                
                // Proceed to exam
                [self showGuidedAccessWarning];
                
            }
            // Guided Access off
            else if (_guidedAccessWarningDisplayed) {
                // Guided Access warning was already displayed: dismiss it
                [_alertController dismissViewControllerAnimated:NO completion:nil];
                _alertController = nil;
                _guidedAccessWarningDisplayed = false;
                _guidedAccessActive = false;
                [self showRestartGuidedAccess];
            }
        }
    }
}


- (void) startAutonomousSingleAppMode
{
    _finishedStartingUp = true;
    if (UIAccessibilityIsGuidedAccessEnabled() == false) {
        NSLog(@"Requesting Autonomous Single App Mode");
        _ASAMActive = true;
        UIAccessibilityRequestGuidedAccessSession(true, ^(BOOL didSucceed) {
            if (didSucceed) {
                NSLog(@"Entered Autonomous Single App Mode");
                [self startExam];
            }
            else {
                NSLog(@"Failed to enter Autonomous Single App Mode");
                _ASAMActive = false;
                [self showStartGuidedAccess];
            }
        });
    } else {
        // Guided Access or ASAM is already active (maybe because of a crash)
        // Try to switch ASAM off to find out if it was active
        _ASAMActive = true;
        UIAccessibilityRequestGuidedAccessSession(false, ^(BOOL didSucceed) {
            if (didSucceed) {
                NSLog(@"Exited Autonomous Single App Mode");
                _ASAMActive = false;
//                // Restart ASAM properly again
//                [self startAutonomousSingleAppMode];
            }
            else {
                NSLog(@"Failed to exit Autonomous Single App Mode, Guided Access must be active");
                _ASAMActive = false;
            }
        });
    }
}


- (void) stopAutonomousSingleAppMode
{
    NSLog(@"Requesting to exit Autonomous Single App Mode");
    UIAccessibilityRequestGuidedAccessSession(false, ^(BOOL didSucceed) {
        if (didSucceed) {
            NSLog(@"Exited Autonomous Single App Mode");
//            _ASAMActive = false;
        }
        else {
            NSLog(@"Failed to exit Autonomous Single App Mode");
        }
    });
}


- (void) showStartGuidedAccess
{
    // First check if a quit password is set
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSString *hashedQuitPassword = [preferences secureObjectForKey:@"org_safeexambrowser_SEB_hashedQuitPassword"];
    if (hashedQuitPassword.length == 0) {
        // No quit password set in current settings: Don't ask user to switch on Guided Access
        // and open an exam portal page or a mock exam (which don't need to be secured)
        _guidedAccessActive = false;
        [self startExam];
    } else {
        // A quit password is set: Ask user to switch on Guided Access
        _guidedAccessActive = true;
        if (UIAccessibilityIsGuidedAccessEnabled() == false) {
            _alertController = [UIAlertController  alertControllerWithTitle:NSLocalizedString(@"Start Guided Access", nil)
                                                                    message:NSLocalizedString(@"Enable Guided Access in Settings -> General -> Accessibility and after returning to SEB, triple click home button to proceed to exam.", nil)
                                                             preferredStyle:UIAlertControllerStyleAlert];
            [self presentViewController:_alertController animated:YES completion:nil];
        }
    }
}


- (void) showRestartGuidedAccess {
    // First check if a quit password is set
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSString *hashedQuitPassword = [preferences secureObjectForKey:@"org_safeexambrowser_SEB_hashedQuitPassword"];
    if (hashedQuitPassword.length > 0) {
        // A quit password is set in current settings: Ask user to restart Guided Access
        // If Guided Access isn't already on, show alert to switch it on again
        if (UIAccessibilityIsGuidedAccessEnabled() == false) {
            _alertController = [UIAlertController  alertControllerWithTitle:NSLocalizedString(@"Restart Guided Access", nil)
                                                                    message:NSLocalizedString(@"Activate Guided Access with triple click home button to return to exam.", nil)
                                                             preferredStyle:UIAlertControllerStyleAlert];
            _guidedAccessActive = true;
            [self presentViewController:_alertController animated:YES completion:nil];
        }
    } else {
        // If no quit password is defined, then we can restart the exam / reload the start page directly
        [self startExam];
    }
}


- (void) showGuidedAccessWarning
{
    // If Guided Access switched on
    if (UIAccessibilityIsGuidedAccessEnabled() == true) {
        // Proceed to exam
        [_alertController dismissViewControllerAnimated:NO completion:nil];
        
        _alertController = [UIAlertController  alertControllerWithTitle:NSLocalizedString(@"Guided Access Warning", nil)
                                                                          message:NSLocalizedString(@"Don't switch Guided Access off (home button triple click or Touch ID) before submitting your exam, otherwise SEB will lock access to the exam! SEB will notify you when you're allowed to switch Guided Access off.", nil)
                                                                   preferredStyle:UIAlertControllerStyleAlert];
        [_alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"I Understand", nil)
                                                                       style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                                                           [_alertController dismissViewControllerAnimated:NO completion:nil];
                                                                           _alertController = nil;
                                                                           _guidedAccessWarningDisplayed = false;
                                                                           
                                                                           [self startExam];
        }]];
        _guidedAccessWarningDisplayed = true;
        [self presentViewController:_alertController animated:YES completion:nil];
    }
}


- (void) correctPasswordEntered {
    // If necessary show the dialog to start Guided Access again
    [self showRestartGuidedAccess];

    // If Guided Access is already switched on, close lockdown window
    if (UIAccessibilityIsGuidedAccessEnabled() == true) {
        [_lockedViewController shouldCloseLockdownWindows];
    }
}


- (void) startExam {
    _examRunning = true;

    // Load all open web pages from the persistent store and re-create webview(s) for them
    // or if no persisted web pages are available, load the start URL
    [_browserTabViewController loadPersistedOpenWebPages];
}


- (void) quitExamConditionally
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSString *hashedQuitPassword = [preferences secureObjectForKey:@"org_safeexambrowser_SEB_hashedQuitPassword"];
    if ([preferences secureBoolForKey:@"org_safeexambrowser_SEB_allowQuit"] == YES) {
        // if quitting SEB is allowed
        if (![hashedQuitPassword isEqualToString:@""]) {
            // if quit password is set, then restrict quitting
            // Allow up to 5 attempts for entering decoding password
            attempts = 5;
            NSString *enterPasswordString = NSLocalizedString(@"Enter quit password:", nil);
            
            // Ask the user to enter the quit password and proceed to the callback method after this happend
            if (!_configFileController) {
                _configFileController = [[SEBiOSConfigFileController alloc] init];
                _configFileController.sebViewController = self;
            }
            
            [_configFileController promptPasswordWithMessageText:enterPasswordString
                                                       title:NSLocalizedString(@"Quit Exam",nil)
                                                    callback:self
                                                    selector:@selector(quitPasswordEntered:)];
        } else {
            // if no quit password is required, then confirm quitting
            _alertController = [UIAlertController  alertControllerWithTitle:NSLocalizedString(@"Quit Exam", nil)
                                                                    message:NSLocalizedString(@"Are you sure you want to quit the exam?", nil)
                                                             preferredStyle:UIAlertControllerStyleAlert];
            [_alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Quit", nil)
                                                                     style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                                                         [_alertController dismissViewControllerAnimated:NO completion:nil];
                                                                         [self quitExam];
                                                                     }]];

            [_alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                                 style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
//                                                                     [_alertController dismissViewControllerAnimated:NO completion:nil];
                                                                 }]];
            
            [self presentViewController:_alertController animated:YES completion:nil];
        }
    }
}


- (void) quitPasswordEntered:(NSString *)password
{
    // Check if the cancel button was pressed
    if (!password) {
        return;
    }
    
    // Get quit password hash from current client settings
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSString *hashedQuitPassword = [preferences secureObjectForKey:@"org_safeexambrowser_SEB_hashedQuitPassword"];
    hashedQuitPassword = [hashedQuitPassword uppercaseString];
    
    SEBKeychainManager *keychainManager = [[SEBKeychainManager alloc] init];
    NSString *hashedPassword = [keychainManager generateSHAHashString:password];
    hashedPassword = [hashedPassword uppercaseString];
    
    attempts--;
    
    if ([hashedPassword caseInsensitiveCompare:hashedQuitPassword] != NSOrderedSame) {
        // wrong password entered, are there still attempts left?
        if (attempts > 0) {
            // Let the user try it again
            NSString *enterPasswordString = NSLocalizedString(@"Wrong password! Try again to enter the quit password:",nil);
            // Ask the user to enter the settings password and proceed to the callback method after this happend
            [_configFileController promptPasswordWithMessageText:enterPasswordString
                                                           title:NSLocalizedString(@"Quit Exam",nil)
                                                        callback:self
                                                        selector:@selector(quitPasswordEntered:)];
            return;
            
        } else {
            // Wrong password entered in the last allowed attempts: Stop quitting the exam
            DDLogError(@"%s: Couldn't quit the exam: The correct quit password wasn't entered.", __FUNCTION__);
            
            NSString *title = NSLocalizedString(@"Cannot Quit Exam", nil);
            NSString *informativeText = NSLocalizedString(@"If you don't enter the correct quit password, then you cannot quit the exam.", nil);
            [_configFileController showAlertWithTitle:title andText:informativeText];
            return;
        }
        
    } else {
        // The correct quit password was entered
        [self quitExam];
    }
}


- (void) quitExam
{
    // Close browser tabs and reset SEB settings to the local client settings if necessary
    [self resetSEB];
    
    if (_ASAMActive) {
        [self stopAutonomousSingleAppMode];
        _ASAMActive = false;
        _alertController = [UIAlertController  alertControllerWithTitle:NSLocalizedString(@"Restart Exam", nil)
                                                                message:NSLocalizedString(@"Return to start page and lock device into SEB.", nil)
                                                         preferredStyle:UIAlertControllerStyleAlert];
        [_alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                             style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                                                 [_alertController dismissViewControllerAnimated:NO completion:nil];
                                                                 [self startAutonomousSingleAppMode];
                                                             }]];
        _guidedAccessWarningDisplayed = true;
        [self presentViewController:_alertController animated:YES completion:nil];
    } else if (_guidedAccessActive) {
        _alertController = [UIAlertController  alertControllerWithTitle:NSLocalizedString(@"Stop Guided Access", nil)
                                                                    message:NSLocalizedString(@"You can now switch off Guided Access by home button triple click or Touch ID.", nil)
                                                             preferredStyle:UIAlertControllerStyleAlert];
        _guidedAccessWarningDisplayed = true;
        [self presentViewController:_alertController animated:YES completion:nil];
    } else {
        // When Guided Access is off, then we can restart SEB with the start URL in local client settings
        [self startExam];
    }
}


// Inform the callback method if decrypting, parsing and storing new settings was successful or not
- (void) quitExamWithCallback:(id)callback selector:(SEL)selector
{
    BOOL success = true;
    IMP imp = [callback methodForSelector:selector];
    void (*func)(id, SEL, BOOL) = (void *)imp;
    func(callback, selector, success);
}


- (void) resetSEB
{
    [_browserTabViewController closeAllTabs];
    _examRunning = false;
    
    // Switch to system's (persisted) UserDefaults
    [NSUserDefaults setUserDefaultsPrivate:NO];
}


- (void) downloadAndOpenSEBConfigFromURL:(NSURL *)url
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    if ([preferences secureBoolForKey:@"org_safeexambrowser_SEB_downloadAndOpenSebConfig"]) {
        // Check if SEB is in exam mode = private UserDefauls are switched on
        if (NSUserDefaults.userDefaultsPrivate) {
            // If yes, we don't download the .seb file
            if (_alertController) {
                [_alertController dismissViewControllerAnimated:NO completion:nil];
            }
            _alertController = [UIAlertController  alertControllerWithTitle:NSLocalizedString(@"Loading New SEB Settings Not Allowed!", nil)
                                                                              message:NSLocalizedString(@"SEB is already running in exam mode and it is not allowed to interupt this by starting another exam. Finish the exam and use a quit link or the quit button in SEB before starting another exam.", nil)
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [_alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                                           style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                                                               [_alertController dismissViewControllerAnimated:NO completion:nil];
                                                                           }]];
            [self presentViewController:_alertController animated:YES completion:nil];

        } else {
            // SEB isn't in exam mode: reconfiguring is allowed
            NSError *error = nil;
            NSData *sebFileData;
            // Download the .seb file directly into memory (not onto disc like other files)
            if ([url.scheme isEqualToString:@"seb"]) {
                // If it's a seb:// URL, we try to download it by http
                NSURL *httpURL = [[NSURL alloc] initWithScheme:@"http" host:url.host path:url.path];
                sebFileData = [NSData dataWithContentsOfURL:httpURL options:NSDataReadingUncached error:&error];
                if (error) {
                    // If that didn't work, we try to download it by https
                    NSURL *httpsURL = [[NSURL alloc] initWithScheme:@"https" host:url.host path:url.path];
                    sebFileData = [NSData dataWithContentsOfURL:httpsURL options:NSDataReadingUncached error:&error];
                    // Still couldn't download the .seb file: present an error and abort
                    if (error) {
//                        [_mainBrowserWindow presentError:error modalForWindow:_mainBrowserWindow delegate:nil didPresentSelector:NULL contextInfo:NULL];
                        return;
                    }
                }
            } else if ([url.scheme isEqualToString:@"sebs"]) {
                // If it's a sebs:// URL, we try to download it by https
                NSURL *httpsURL = [[NSURL alloc] initWithScheme:@"https" host:url.host path:url.path];
                sebFileData = [NSData dataWithContentsOfURL:httpsURL options:NSDataReadingUncached error:&error];
                // Couldn't download the .seb file: present an error and abort
                if (error) {
//                    [_mainBrowserWindow presentError:error modalForWindow:_mainBrowserWindow delegate:nil didPresentSelector:NULL contextInfo:NULL];
                    return;
                }
            } else {
                sebFileData = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:&error];
                if (error) {
//                    [_mainBrowserWindow presentError:error modalForWindow:_mainBrowserWindow delegate:nil didPresentSelector:NULL contextInfo:NULL];
                }
            }
            _configFileController = [[SEBiOSConfigFileController alloc] init];
            _configFileController.sebViewController = self;
            
            // Get current config path
            currentConfigPath = [[MyGlobals sharedMyGlobals] currentConfigURL];
            // Store the URL of the .seb file as current config file path
            [[MyGlobals sharedMyGlobals] setCurrentConfigURL:[NSURL URLWithString:url.lastPathComponent]]; // absoluteString]];
            
            [_configFileController storeNewSEBSettings:sebFileData forEditing:false callback:self selector:@selector(storeNewSEBSettingsSuccessful:)];
        }
    }
}


- (void) storeNewSEBSettingsSuccessful:(BOOL)success
{
    if (success) {
        [_browserTabViewController closeAllTabs];
        _examRunning = false;

        [self startAutonomousSingleAppMode];

        
//        // Post a notification that it was requested to restart SEB with changed settings
//        [[NSNotificationCenter defaultCenter]
//         postNotificationName:@"requestRestartNotification" object:self];
        
    } else {
        // if decrypting new settings wasn't successfull, we have to restore the path to the old settings
        [[MyGlobals sharedMyGlobals] setCurrentConfigURL:currentConfigPath];
    }
}


- (void)searchStarted
{
    [self.mm_drawerController closeDrawerAnimated:YES completion:nil];
    
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    
    UIBarButtonItem *cancelSearchButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(searchButtonCancel:)];
    
    UIBarButtonItem *padding = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    [padding setWidth:13];
    
    [self.navigationItem setRightBarButtonItems:
     [NSArray arrayWithObjects:cancelSearchButton, padding, nil] animated:YES];
}


- (void)searchButtonCancel:(id)sender
{
    [_searchBarViewController cancelButtonPressed];
}


- (void)searchStopped
{
    [self.navigationItem setLeftBarButtonItem:leftButton animated:YES];
    
    //    [_navigationItem setRightBarButtonItems:[NSArray arrayWithObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addPageButton:)]] animated:YES];
}


- (void)searchGoSearchString:(NSString *)searchString
{
    [self searchStopped];
    [_browserTabViewController loadWebPageOrSearchResultWithString:searchString];
}


- (void) didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end