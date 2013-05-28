//
//  Model.h
//  iORM
//
//  Created by Maxime Guilbot on 7/12/12.
//  Copyright (c) 2012 Ekohe. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFHTTPClient.h"

@class Model;

@interface Model : NSObject {
    NSDictionary *errors;
}

@property (nonatomic, strong) NSString *id;

+ (AFHTTPClient*)sharedClient;

// Class methods
+(void) all:(void (^)(NSArray* objects))success failure:(void (^)(NSError* error))failure;
+(void) allWithParameters:(NSDictionary*)parameters success:(void (^)(NSArray* objects))success failure:(void (^)(NSError* error))failure;

// Instance Requests
-(void) create:(void (^)(void))success failure:(void (^)(void))failure;
-(void) postTo:(NSString*)path success:(void (^)(void))success failure:(void (^)(void))failure;
-(void) postTo:(NSString*)path attributes:(NSDictionary*)attributes success:(void (^)(void))success failure:(void (^)(void))failure;


-(void) save:(void (^)(void))success failure:(void (^)(NSError* error))failure;
-(void) destroy:(void (^)(void))success failure:(void (^)(NSError* error))failure;

// Has many
-(void) fetchMany:(NSString*)relation success:(void (^)(void))success failure:(void (^)(NSError* error))failure;
-(void) push:(Model*)object to:(NSString*)relation success:(void (^)(void))success failure:(void (^)(NSError* error))failure;

// Path
-(NSString*) path;

// State
-(BOOL) persistent;

// Attributes
-(void) updateAttributes:(NSDictionary*)attributes;
-(NSDictionary*) attributes;
-(BOOL) isEqualTo:(Model*)object;

// Errors
-(NSDictionary*) errors;
-(BOOL) hasErrors;
-(NSString*) errorMessage;

// Misc.
-(Model*) duplicate;

// Rendering
-(void) render:(UIViewController*)viewController;
-(void) fillForm:(UIViewController*)viewController;
-(Model*) updateFromForm:(UIViewController*)viewController;

@end
