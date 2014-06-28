//
//  FirstViewController.m
//  social-network-integration
//
//  Created by Maxim on 6/27/14.
//  Copyright (c) 2014 Maxim Letushov. All rights reserved.
//

#import "FirstViewController.h"
#import "TwitterLoginProxy.h"

@interface FirstViewController ()

@end

@implementation FirstViewController

- (IBAction)getMyInfo:(id)sender {
    [TwitterLoginProxy loginWithSuccessHandler:^(STTwitterAPI *twitter, NSString *screenName) {
        [twitter getUserInformationFor:screenName successBlock:^(NSDictionary *user) {
            NSLog(@"%@", user);
        } errorBlock:^(NSError *error) {
            NSLog(@"%@", error);
        }];
    } errorHandler:^(NSError *error) {
        
    }];
}

@end
