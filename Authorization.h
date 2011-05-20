//
//  Authorization.h
//
//  Created by Maxime Guilbot on 12/8/10.
//  Copyright 2010 ekohe. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Authorization : NSObject {
}

+(void) deleteAuthorization;

// Cookies
+(void) setCookies:(NSArray*)cookies;
+(NSArray*) cookies;

@end
