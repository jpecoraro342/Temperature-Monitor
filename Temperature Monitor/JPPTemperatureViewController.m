//
//  JPPTemperaturViewController.m
//  Temperature Monitor
//
//  Created by Joseph Pecoraro on 7/30/14.
//
//

#import "JPPTemperatureViewController.h"
#import <FYX/FYX.h>
#import <FYX/FYXVisitManager.h>
#import <FYX/FYXTransmitter.h>

@interface JPPTemperatureViewController () <FYXServiceDelegate, FYXVisitDelegate, UITextFieldDelegate>

@property (weak, nonatomic) IBOutlet UILabel *lastUpdatedLabel;
@property (weak, nonatomic) IBOutlet UILabel *temperatureLabel;
@property (weak, nonatomic) IBOutlet UITextField *upperLimit;
@property (weak, nonatomic) IBOutlet UITextField *lowerLimit;

@property (nonatomic, strong) FYXVisitManager *visitManager;

@property (nonatomic, strong) NSDate *lastColdNotification;
@property (nonatomic, strong) NSDate *lastHotNotification;

@property (nonatomic, assign) NSInteger highTemp;
@property (nonatomic, assign) NSInteger lowTemp;

@property (nonatomic, strong) NSMutableArray *temperatureChangeHistory;
@property (nonatomic, strong) NSMutableArray *timeOfTemperatureChange;

@property (nonatomic, strong) NSMutableSet *ignoredBeacons;

@property (nonatomic, strong) NSDateFormatter *dateFormatter;

@end

@implementation JPPTemperatureViewController

-(instancetype)init {
    self = [super init];
    if (self) {
        self.highTemp = 80;
        self.lowTemp = 68;
        _dateFormatter = [[NSDateFormatter alloc] init];
        [self.dateFormatter setDateFormat:@"EEE HH:mm a"];
        self.ignoredBeacons = [[NSMutableSet alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self loadFromDefaults];
    
    [self.upperLimit setText:[NSString stringWithFormat:@"%zd", self.highTemp]];
    [self.lowerLimit setText:[NSString stringWithFormat:@"%zd", self.lowTemp]];
    
    [FYX startService:self];
}

-(void)loadFromDefaults {
    self.temperatureLabel.text = [[[NSUserDefaults standardUserDefaults] objectForKey:@"temperature"] stringValue] ?: @"74";
    self.lastUpdatedLabel.text = [NSString stringWithFormat:@"Last Updated: %@", [self.dateFormatter stringFromDate:[[NSUserDefaults standardUserDefaults] objectForKey:@"dateLastUpdated"]]];
}

#pragma mark Gimbal FYXServiceDelegate

- (void)serviceStarted {
    // this will be invoked if the service has successfully started
    // bluetooth scanning will be started at this point.
    self.visitManager = [FYXVisitManager new];
    self.visitManager.delegate = self;
    [self.visitManager start];
}

- (void)startServiceFailed:(NSError *)error {
    // this will be called if the service has failed to start
    NSLog(@"FYX Service Start Failed:\n%@", error);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSLog(@"viewDidLoad called");
        //wait 3 seconds before exiting
        sleep(2);
        NSLog(@"Returning to Main View");
        sleep(1);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:YES];
        });
        
    });
}

#pragma mark Gimbal FYXVisitDelegate

- (void)didArrive:(FYXVisit *)visit; {
    // this will be invoked when an authorized transmitter is sighted for the first time
    NSLog(@"\nBeacon Found\nName: %@\nTemperature: %@\nBattery: %@\n\n", visit.transmitter.name, visit.transmitter.temperature, visit.transmitter.battery);
    [self setTemperature:visit.transmitter.temperature];
}
- (void)receivedSighting:(FYXVisit *)visit updateTime:(NSDate *)updateTime RSSI:(NSNumber *)RSSI; {
    
    if ([self.ignoredBeacons containsObject:visit.transmitter.identifier]) {
        return;
    }
    else if (![visit.transmitter.identifier isEqualToString:@"9as6-mrnmg"]) {
        NSLog(@"\nIgnoring Beacon\nID: %@", visit.transmitter.identifier);
        [self.ignoredBeacons addObject:visit.transmitter.identifier];
        return;
    }
    
    NSLog(@"\nReceived Signal\nName: %@\nSignal: %@db\nTemperature: %@f\nBattery: %@\n\n", visit.transmitter.name, RSSI, visit.transmitter.temperature, visit.transmitter.battery);
    [self setTemperature:visit.transmitter.temperature];
    
    if ([visit.transmitter.temperature integerValue] > self.highTemp) {
        [self sendHighTemperatureNotification];
    }
    else if ([visit.transmitter.temperature integerValue] < self.lowTemp) {
        [self sendLowTemperatureNotification];
    }
}

- (void)didDepart:(FYXVisit *)visit; {
    // this will be invoked when an authorized transmitter has not been sighted for some time
    NSLog(@"\n%@ has exited range\nBeacon was in proximity for %.2f seconds\n\n", visit.transmitter.name, visit.dwellTime);
}

#pragma mark TextField Delegate

- (IBAction)backgroundTapped:(id)sender {
    [self.view endEditing:YES];
}

-(BOOL)textFieldShouldEndEditing:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

-(void)textFieldDidEndEditing:(UITextField *)textField {
    NSInteger value = [textField.text integerValue];
    if ([textField isEqual:self.upperLimit]) {
        if (value > self.lowTemp) {
            self.highTemp = value;
        }
        else {
            [self.upperLimit setText:[NSString stringWithFormat:@"%zd", self.highTemp]];
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Could Not Set Upper Limit" message:@"Upper limit should have a higher magnitude than the lower limit" delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil];
            [alert show];
        }
    }
    else if ([textField isEqual:self.lowerLimit]) {
        if (value < self.highTemp) {
            self.lowTemp = value;
        }
        else {
            [self.lowerLimit setText:[NSString stringWithFormat:@"%zd", self.lowTemp]];
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Could Not Set Lower Limit" message:@"Lower limit should have a lower magnitude than the upper limit" delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil];
            [alert show];
        }
    }
}

#pragma mark Keyboard Adjustment

//register keyboard notification
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

//remove keyboard notification observer
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

//show/hide the keyboard
- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    CGSize kbSize = [[userInfo objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect f = self.view.frame;
        f.origin.y -= kbSize.height/2 + 10;
        self.view.frame = f;
    }];
}

-(void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    CGSize kbSize = [[userInfo objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect f = self.view.frame;
        f.origin.y += kbSize.height/2 + 10;
        self.view.frame = f;
    }];
}

#pragma mark Private

-(void)setTemperature:(NSNumber *)temperature {
    NSDate *now = [NSDate new];
    [self.temperatureLabel setText:[temperature stringValue]];
    [self.lastUpdatedLabel setText:[NSString stringWithFormat:@"Last Updated: %@", [self.dateFormatter stringFromDate:now]]];
    [[NSUserDefaults standardUserDefaults] setObject:temperature forKey:@"temperature"];
    [[NSUserDefaults standardUserDefaults] setObject:now forKey:@"dateLastUpdated"];
}

-(void)sendHighTemperatureNotification {
    NSDate *now = [NSDate date];
    
    if (self.lastHotNotification) {
        NSTimeInterval timeSinceLastHotNotification = [now timeIntervalSinceDate:self.lastHotNotification];
        
        if (timeSinceLastHotNotification < 1800) {
            return;
        }
    }
    
    self.lastHotNotification = now;
    
    [self sendNotificationWithMessage:@"It's a little bit toasty in here, you should turn on the ac"];
}

-(void)sendLowTemperatureNotification {
    NSDate *now = [NSDate date];
    
    if (self.lastColdNotification) {
        NSTimeInterval timeSinceLastColdNotification = [now timeIntervalSinceDate:self.lastColdNotification];
        
        if (timeSinceLastColdNotification < 1800) {
            return;
        }
    }
    
    self.lastColdNotification = now;
    
    [self sendNotificationWithMessage:@"It's pretty cold, you should turn the ac off"];
}

-(void)sendNotificationWithMessage:(NSString*)message {
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    NSDate *now = [NSDate date];
    
    //one second delay gives the change to put the app in background
    NSDate *dateToFire = [now dateByAddingTimeInterval:1];
    
    [notification setFireDate:dateToFire];
    [notification setAlertBody:message];
    NSLog(@"\nNotification Scheduled with Message: %@\n\n", message);
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}




@end
