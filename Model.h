//
//  Model.h
//
//  Created by Pawel Maverick Stoklosa III on 10/14/10.
//  Copyright 2010 ekohe. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WebServiceRequest.h"

@class Model;

@protocol ModelDelegate
@optional
-(void) all:(Class)klass objects:(NSArray*)objects;
-(void) first:(Model*)model;
-(void) modelGotDetails:(Model*)model;
-(void) modelUpdated:(Model*)model;
@end


@interface Model : NSObject <JSONRequestDelegate> {
    NSNumber *objectId;
    WebServiceRequest *detailsRequest;
    id<ModelDelegate> gotDetailsDelegate;
    WebServiceRequest *refreshRequest;
	id<ModelDelegate> refreshDelegate;
}

@property (nonatomic,retain) WebServiceRequest *detailsRequest;
@property (nonatomic,retain) NSNumber *objectId;
@property (nonatomic,assign) id<ModelDelegate> gotDetailsDelegate;
@property (nonatomic,retain) WebServiceRequest *refreshRequest;
@property (nonatomic,assign) id<ModelDelegate> refreshDelegate;

-(id) initWithJson:(NSDictionary*)json;
-(void) addDetailsWithJson:(NSDictionary*)json;
-(void) updateModelWithJson:(NSDictionary*)json;
+(NSString*) getPath;

// Finders
+(void)getAllFromPath:(NSString*)path delegate:(id)delegate;
+(void)getAllFromPath:(NSString*)path delegate:(id)delegate withHud:(BOOL)displayHud;
+(void)getAllFromPath:(NSString*)path withParameters:(NSDictionary*)params delegate:(id)delegate;
+(void)getAllFromPath:(NSString*)path withParameters:(NSDictionary*)params delegate:(id)delegate withHud:(BOOL)displayHud;

+(void)getAllWithParameters:(NSDictionary*)params delegate:(id)delegate withHud:(BOOL)displayHud;
+(void)getAllWithParameters:(NSDictionary*)params delegate:(id)delegate;
+(void)getAllWithDelegate:(id)delegate withHud:(BOOL)displayHud;
+(void)getAllWithDelegate:(id)delegate;

+(void)cancelAll;

+(void)firstWithId:(int)objectId withDelegate:(id)delegate;
+(void)firstWithPath:(NSString*)path withDelegate:(id)delegate;
+(void)cancelFirst;

+(id)firstDelegate;
+(void)setFirstDelegate:(id<ModelDelegate>)newFirstDelegate;
+(id)allDelegate;
+(void)setAllDelegate:(id<ModelDelegate>)newAllDelegate;

-(void)getDetailsWithDelegate:(id<ModelDelegate>)delegate;

// Refresh
-(void)refreshWithDelegate:(id<ModelDelegate>)delegate;
-(void)refreshWithPath:(NSString*)path withDelegate:(id<ModelDelegate>)delegate;
-(void)refreshWithPath:(NSString*)path withDelegate:(id<ModelDelegate>)delegate withHud:(BOOL)displayHud;
@end
