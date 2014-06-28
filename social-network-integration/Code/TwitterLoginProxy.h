//
//  TwitterLoginProxy.h
//  social-network-integration
//
//  Created by Maxim on 6/27/14.
//  Copyright (c) 2014 Maxim Letushov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "STTwitter.h"

typedef void(^TwitterLoginProxySuccessHandler)(STTwitterAPI *twitter, NSString *screenName);
typedef void(^TwitterLoginProxyErrorHandler)(NSError *);


@interface TwitterLoginProxy : NSObject

@property (nonatomic, assign) BOOL forceToLoginViaSafari;   //default is NO
@property (nonatomic, assign) BOOL shouldStoreAccountOnOSTwitterSettingsAfterLoginViaSafari; //default is YES

@property (nonatomic, strong) NSString *consumerKey;
@property (nonatomic, strong) NSString *consumerSecret;

+ (instancetype)shared;

+ (void)loginWithSuccessHandler:(TwitterLoginProxySuccessHandler)successHandler
                   errorHandler:(TwitterLoginProxyErrorHandler)errorHandler;

+ (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation;

@end


/*

 STTwitterOSSystemCannotAccessTwitter
 STTwitterOSCannotFindTwitterAccount
 STTwitterOSUserDeniedAccessToTheirAccounts
 STTwitterOSNoTwitterAccountIsAvailable
*/
