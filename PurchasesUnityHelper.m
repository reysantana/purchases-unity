//
//  PurchasesUnityHelper.m
//
//  Created by RevenueCat, Inc. on 5/30/18.
//

#import <Foundation/Foundation.h>
#import <Purchases/RCPurchases.h>
#import <Purchases/RCPurchaserInfo.h>
#import <StoreKit/StoreKit.h>

#pragma mark Utility Methods

NSString *convertCString(const char* string) {
    if (string)
        return [NSString stringWithUTF8String:string];
    else
        return nil;
}

char* makeStringCopy(NSString* nstring) {
    if ((!nstring) || (nil == nstring) || ( nstring == (id)[NSNull null] ) || (0 == nstring.length))
        return NULL;

    const char* string = [nstring UTF8String];

    if (string == NULL)
        return NULL;

    char* res = (char*)malloc(strlen(string) + 1);
    strcpy(res, string);

    return res;
}

#pragma mark RCPurchases Wrapper

@interface RCUnityHelperDelegate : NSObject <RCPurchasesDelegate>
@property (nonatomic) RCPurchases *purchases;
@property (nonatomic) NSDictionary *products;
@property (nonatomic) NSString *gameObject;
@end

@implementation RCUnityHelperDelegate

- (void)setupPurchases:(NSString *)apiKey appUserID:(NSString *)appUserID gameObject:(NSString *)gameObject
{
    self.purchases.delegate = nil;
    self.products = nil;
    self.gameObject = nil;

    self.purchases = [[RCPurchases alloc] initWithAPIKey:apiKey appUserID:appUserID];
    self.gameObject = gameObject;
    self.purchases.delegate = self;
}

- (NSDictionary *)productJSON:(SKProduct *)p
{
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterCurrencyStyle;
    formatter.locale = p.priceLocale;
    NSDictionary *d = @{
                            @"identifier": p.productIdentifier ?: @"",
                            @"description": p.localizedDescription ?: @"",
                            @"title": p.localizedTitle ?: @"",
                            @"price": @(p.price.floatValue),
                            @"priceString": [formatter stringFromNumber:p.price]
                        };
    return d;
}

- (NSDictionary *)errorJSON:(NSError *)error
{
    return @{
             @"message": error.localizedDescription,
             @"code": @(error.code),
             @"domain": error.domain
             };
}

- (NSDictionary *)purchaserInfoJSON:(RCPurchaserInfo *)info
{
    NSArray *productIdentifiers = info.allPurchasedProductIdentifiers.allObjects;
    NSArray *sorted = [productIdentifiers sortedArrayUsingSelector:@selector(compare:)];

    NSMutableArray *expirationDateKeys = [NSMutableArray new];
    NSMutableArray *expirationDateValues = [NSMutableArray new];

    for (NSString *productIdentifier in sorted) {
        NSDate *date = [info expirationDateForProductIdentifier:productIdentifier];
        if (date) {
            [expirationDateKeys addObject:productIdentifier];
            [expirationDateValues addObject:@(date.timeIntervalSince1970)];
        }
    }
    
    return @{
             @"activeSubscriptions": info.activeSubscriptions.allObjects,
             @"allPurchasedProductIdentifiers": info.allPurchasedProductIdentifiers.allObjects,
             @"latestExpirationDate": info.latestExpirationDate ? @(info.latestExpirationDate.timeIntervalSince1970) : [NSNull null],
             @"allExpirationDateKeys": expirationDateKeys,
             @"allExpirationDateValues": expirationDateValues
             };
}

- (void)getProducts:(NSArray *)productIdentifiers
               type:(NSString *)type
{
    [self.purchases productsWithIdentifiers:productIdentifiers
                                 completion:^(NSArray<SKProduct *> * _Nonnull products) {
                                     NSMutableDictionary *productByID = [NSMutableDictionary new];
                                     NSMutableArray *productObjects = [NSMutableArray new];

                                     for (SKProduct *p in products) {
                                         productByID[p.productIdentifier] = p;
                                         [productObjects addObject:[self productJSON:p]];
                                     }

                                     self.products = [NSDictionary dictionaryWithDictionary:productByID];
                                     [self sendProducts:productObjects];
                                 }];
}

- (void)makePurchase:(NSString *)productIdentifier
{
    SKProduct *product = self.products[productIdentifier];
    if (product == nil)
    {
        NSLog(@"No product found for identifier %@", productIdentifier);
        return;
    }

    [self.purchases makePurchase:product];
}

- (void)sendJSONObject:(NSDictionary *)jsonObject toMethod:(NSString *)methodName
{
    NSError *error = nil;
    NSData *responseJSONData = [NSJSONSerialization dataWithJSONObject:jsonObject options:0 error:&error];

    if (error)
    {
        NSLog(@"Error serializing products: %@", error.localizedDescription);
        return;
    }

    if (responseJSONData)
    {
        NSString *json = [[NSString alloc] initWithData:responseJSONData encoding:NSUTF8StringEncoding];
        NSLog(@"json = %@", json);
        UnitySendMessage(self.gameObject.UTF8String, methodName.UTF8String, json.UTF8String);
    }
}

- (void)sendProducts:(NSArray *)productObjects
{
    NSDictionary *response = @{
                              @"products": productObjects
                              };
    [self sendJSONObject:response toMethod:@"_receiveProducts"];
}

- (void)sendPurchaserInfo:(RCPurchaserInfo *)info
     completedTransaction:(SKPaymentTransaction *)transaction
                    error:(NSError *)error
{
    NSMutableDictionary *response = [NSMutableDictionary new];

    if (transaction)
    {
        response[@"productIdentifier"] = transaction.payment.productIdentifier;
    }

    if (info)
    {
        response[@"purchaserInfo"] = [self purchaserInfoJSON:info];
    }

    if (error)
    {
        response[@"error"] = [self errorJSON:error];
    }
    
    [self sendJSONObject:response toMethod:@"_receivePurchaserInfo"];
}

- (void)purchases:(nonnull RCPurchases *)purchases
completedTransaction:(nonnull SKPaymentTransaction *)transaction
  withUpdatedInfo:(nonnull RCPurchaserInfo *)purchaserInfo {
    [self sendPurchaserInfo:purchaserInfo completedTransaction:transaction error:nil];
}

- (void)purchases:(nonnull RCPurchases *)purchases failedToUpdatePurchaserInfoWithError:(nonnull NSError *)error {
    [self sendPurchaserInfo:nil completedTransaction:nil error:error];
}

- (void)purchases:(nonnull RCPurchases *)purchases failedTransaction:(nonnull SKPaymentTransaction *)transaction withReason:(nonnull NSError *)failureReason {
    [self sendPurchaserInfo:nil completedTransaction:transaction error:failureReason];
}

- (void)purchases:(nonnull RCPurchases *)purchases receivedUpdatedPurchaserInfo:(nonnull RCPurchaserInfo *)purchaserInfo {
    [self sendPurchaserInfo:purchaserInfo completedTransaction:nil error:nil];
}

@end

#pragma mark Bridging Methods

static RCUnityHelperDelegate *_RCUnityHelper;

static RCUnityHelperDelegate *_RCUnityHelperShared()
{
    if (_RCUnityHelper == nil) {
        _RCUnityHelper = [[RCUnityHelperDelegate alloc] init];
    }
    return _RCUnityHelper;
}

void _RCSetupPurchases(const char *gameObject, const char *apiKey, const char *appUserID)
{
    [_RCUnityHelperShared() setupPurchases:convertCString(apiKey) appUserID:convertCString(appUserID) gameObject:convertCString(gameObject)];
}

void _RCGetProducts(const char *productIdentifiersJSON, const char *type)
{
    NSError *error = nil;
    NSDictionary *productsRequest = [NSJSONSerialization JSONObjectWithData:[convertCString(productIdentifiersJSON) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];

    if (error)
    {
        NSLog(@"Error parsing productIdentifiers JSON: %s %@", productIdentifiersJSON, error.localizedDescription);
        return;
    }

    [_RCUnityHelperShared() getProducts:productsRequest[@"productIdentifiers"] type:convertCString(type)];
}

void _RCMakePurchase(const char *productIdentifier, const char *type)
{
    [_RCUnityHelperShared() makePurchase:convertCString(productIdentifier)];
}


