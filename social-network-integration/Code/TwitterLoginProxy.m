//
//  TwitterLoginProxy.m
//  social-network-integration
//
//  Created by Maxim on 6/27/14.
//  Copyright (c) 2014 Maxim Letushov. All rights reserved.
//

#import "TwitterLoginProxy.h"
#import <STTwitterAPI.h>
#import <STTwitterOS.h>
#import <Accounts/Accounts.h>
#import "DDLog.h"


#ifdef DEBUG
static const int ddLogLevel = LOG_LEVEL_VERBOSE;
#else
static const int ddLogLevel = LOG_LEVEL_WARN;
#endif

static NSString *const kSuccessHandler = @"success_handler";
static NSString *const kErrorHandler = @"error_handler";


@interface TwitterLoginProxy ()

@property (nonatomic, strong) NSMutableArray *handlersArray;
@property (nonatomic, strong) STTwitterAPI *twitter;
@property (nonatomic, assign) BOOL isLoginInProgress;
@property (nonatomic, assign) BOOL isLoggedIn;
@property (nonatomic, assign) BOOL isLoggedInViaSafari;
@property (nonatomic, strong) NSString *screenName;
@end


@implementation TwitterLoginProxy

+ (instancetype)shared
{
    static TwitterLoginProxy *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [TwitterLoginProxy new];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.isLoggedIn = NO;
        self.isLoggedInViaSafari = NO;
        self.isLoginInProgress = NO;
        
        self.twitter = nil;
        self.handlersArray = [NSMutableArray array];
        
        TwitterLoginProxy *weakSelf __weak = self;
        
        [[NSNotificationCenter defaultCenter] addObserverForName:ACAccountStoreDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
            if (weakSelf.isLoggedIn && !weakSelf.isLoggedInViaSafari) {
                // account must be considered invalid
                weakSelf.isLoggedIn = NO;
            }
        }];
    }
    return self;
}

- (NSDictionary *)parametersDictionaryFromQueryString:(NSString *)queryString {
    
    NSMutableDictionary *md = [NSMutableDictionary dictionary];
    
    NSArray *queryComponents = [queryString componentsSeparatedByString:@"&"];
    
    for(NSString *s in queryComponents) {
        NSArray *pair = [s componentsSeparatedByString:@"="];
        if([pair count] != 2) continue;
        
        NSString *key = pair[0];
        NSString *value = pair[1];
        
        md[key] = value;
    }
    
    return md;
}

+ (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
    if ([[url scheme] isEqualToString:@"myapp"] == NO) return NO;
    
    TwitterLoginProxy *proxy = [self shared];
    
    NSDictionary *d = [proxy parametersDictionaryFromQueryString:[url query]];
    
    NSString *token = d[@"oauth_token"];
    NSString *verifier = d[@"oauth_verifier"];
    
    [proxy setOAuthToken:token oauthVerifier:verifier];
    
    return YES;
}

- (void)setOAuthToken:(NSString *)token oauthVerifier:(NSString *)verifier
{
    TwitterLoginProxy *weakSelf __weak = self;
    
    [self.twitter postAccessTokenRequestWithPIN:verifier successBlock:^(NSString *oauthToken, NSString *oauthTokenSecret, NSString *userID, NSString *screenName) {
        NSLog(@"-- screenName: %@", screenName);
        
        weakSelf.screenName = screenName;
        weakSelf.isLoggedInViaSafari = YES;
        
        [weakSelf handleSuccessLogin];
        
        if (self.shouldStoreAccountOnOSTwitterSettingsAfterLoginViaSafari) {
            [weakSelf storeAccountWithAccessToken:weakSelf.twitter.oauthAccessToken secret:weakSelf.twitter.oauthAccessTokenSecret];
        }
        
        /*
         At this point, the user can use the API and you can read his access tokens with:
         
         _twitter.oauthAccessToken;
         _twitter.oauthAccessTokenSecret;
         
         You can store these tokens (in user default, or in keychain) so that the user doesn't need to authenticate again on next launches.
         
         Next time, just instanciate STTwitter with the class method:
         
         +[STTwitterAPI twitterAPIWithOAuthConsumerKey:consumerSecret:oauthToken:oauthTokenSecret:]
         
         Don't forget to call the -[STTwitter verifyCredentialsWithSuccessBlock:errorBlock:] after that.
         */
        
    } errorBlock:^(NSError *error) {
        [weakSelf handleErrorLogin:error];
    }];
}

+ (void)loginWithSuccessHandler:(TwitterLoginProxySuccessHandler)successHandler
                   errorHandler:(TwitterLoginProxyErrorHandler)errorHandler
{
    TwitterLoginProxy *proxy = [self shared];
    
    [proxy saveSuccessHandler:successHandler errorHandler:errorHandler];
    
    if (proxy.isLoggedIn) {
        [proxy performAllSuccessHandlers];
        return ;
    }
    
    if (proxy.isLoginInProgress) {
        return ;
    }
    
    if (proxy.forceToLoginViaSafari) {
        [proxy loginInSafari];
    } else {
        [proxy loginWithIOS];
    }
}

- (void)saveSuccessHandler:(TwitterLoginProxySuccessHandler)successHandler
              errorHandler:(TwitterLoginProxyErrorHandler)errorHandler
{
    NSMutableDictionary *hadlersDictionary = [NSMutableDictionary dictionary];
    if (successHandler) {
        hadlersDictionary[kSuccessHandler] = [successHandler copy];
    }
    if (errorHandler) {
        hadlersDictionary[kErrorHandler] = [errorHandler copy];
    }
    
    [self.handlersArray addObject:hadlersDictionary];
}

- (void)performAllSuccessHandlers
{
    for (NSDictionary *hadlersDictionary in self.handlersArray) {
        void(^successHandler)(STTwitterAPI *, NSString *) = hadlersDictionary[kSuccessHandler];
        
        if (successHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                successHandler(self.twitter, self.screenName);
            });
        }
    }
    
    [self.handlersArray removeAllObjects];
}

- (void)performAllErrorHandlerWithError:(NSError *)error
{
    for (NSDictionary *hadlersDictionary in self.handlersArray) {
        void(^errorHandler)(NSError *) = hadlersDictionary[kErrorHandler];
        
        if (errorHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                errorHandler(error);
            });
        }
    }
    
    [self.handlersArray removeAllObjects];
}

- (BOOL)isTwitterOSError:(NSInteger)errorCode
{
    return (errorCode == STTwitterOSSystemCannotAccessTwitter ||
            errorCode == STTwitterOSCannotFindTwitterAccount ||
            errorCode == STTwitterOSUserDeniedAccessToTheirAccounts ||
            errorCode == STTwitterOSNoTwitterAccountIsAvailable);
}

- (void)loginWithIOS
{
    [self handleStartLogin];
    
    self.twitter = [STTwitterAPI twitterAPIOSWithFirstAccount];
    
    [self.twitter verifyCredentialsWithSuccessBlock:^(NSString *username) {
        DDLogInfo(@"Logined. Username = %@", username);
        self.screenName = username;
        [self handleSuccessLogin];
        
    } errorBlock:^(NSError *error) {
        if ([self isTwitterOSError:error.code]) {
            [self loginInSafari];
        } else {
            [self handleErrorLogin:error];
        }
    }];
}

- (void)loginInSafari
{
    [self handleStartLogin];
    
    self.twitter = [STTwitterAPI twitterAPIWithOAuthConsumerKey:self.consumerKey
                                                 consumerSecret:self.consumerSecret];
    
    [self.twitter postTokenRequest:^(NSURL *url, NSString *oauthToken) {
        DDLogInfo(@"-- url: %@", url);
        DDLogInfo(@"-- oauthToken: %@", oauthToken);
        
        [[UIApplication sharedApplication] openURL:url];
    } forceLogin:@(YES) screenName:nil oauthCallback:@"myapp://twitter_access_tokens/" errorBlock:^(NSError *error) {
        [self handleErrorLogin:error];
    }];
}

- (void)handleStartLogin
{
    self.isLoginInProgress = YES;
}

- (void)handleSuccessLogin
{
    DDLogInfo(@"Successfully logged in Twitter");
    
    self.isLoginInProgress = NO;
    self.isLoggedIn = YES;
    
    [self performAllSuccessHandlers];
}

- (void)handleErrorLogin:(NSError *)error
{
    DDLogError(@"%@", [error localizedDescription]);
    
    self.isLoginInProgress = NO;
    self.isLoggedIn = NO;
    
    [self performAllErrorHandlerWithError:error];
}

#pragma mark -

- (void)storeAccountWithAccessToken:(NSString *)token secret:(NSString *)secret
{
    // Each account has a credential, which is comprised of a verified token and secret
    
    ACAccountStore *store = [[ACAccountStore alloc] init];
    
    ACAccountCredential *credential = [[ACAccountCredential alloc] initWithOAuthToken:token tokenSecret:secret];
    
    //  Obtain the Twitter account type from the store
    ACAccountType *twitterAcctType = [store accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    
    //  Create a new account of the intended type
    ACAccount *newAccount = [[ACAccount alloc] initWithAccountType:twitterAcctType];
    
    //  Attach the credential for this user
    newAccount.credential = credential;
    
    // Finally, ask the account store instance to save the account Note: that
    // the completion handler is not guaranteed to be executed on any thread,
    // so care should be taken if you wish to update the UI, etc.
    
    [store saveAccount:newAccount withCompletionHandler:^(BOOL success, NSError *error) {
         if (success) {
             // we've stored the account!
             NSLog(@"the account was saved!");
         }
         else {
             //something went wrong, check value of error
             NSLog(@"the account was NOT saved");
             
             // see the note below regarding errors...
             //  this is only for demonstration purposes
             if ([[error domain] isEqualToString:ACErrorDomain]) {
                 
                 // The following error codes and descriptions are found in ACError.h
                 switch ([error code]) {
                     case ACErrorAccountMissingRequiredProperty:
                         NSLog(@"Account wasn't saved because it is missing a required property.");
                         break;
                     case ACErrorAccountAuthenticationFailed:
                         NSLog(@"Account wasn't saved because authentication of the supplied credential failed.");
                         break;
                     case ACErrorAccountTypeInvalid:
                         NSLog(@"Account wasn't saved because the account type is invalid.");
                         break;
                     case ACErrorAccountAlreadyExists:
                         NSLog(@"Account wasn't added because it already exists.");
                         break;
                     case ACErrorAccountNotFound:
                         NSLog(@"Account wasn't deleted because it could not be found.");
                         break;
                     case ACErrorPermissionDenied:
                         NSLog(@"Permission Denied");
                         break;
                     case ACErrorUnknown:
                     default: // fall through for any unknown errors...
                         NSLog(@"An unknown error occurred.");
                         break;
                 }
             } else {
                 // handle other error domains and their associated response codes...
                 NSLog(@"%@", [error localizedDescription]);
             }
         }
     }];
}

@end
