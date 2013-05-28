//
//  NSDate+JSONString.h
//  iORM
//
//  Created by Maxime Guilbot on 7/26/12.
//  Copyright (c) 2012 Ekohe. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDate (JSONString)
+(NSDate*) dateFromJSON:(NSString*)JSONdate;
-(NSString*) jsonString;
@end
