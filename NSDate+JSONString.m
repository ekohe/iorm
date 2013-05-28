//
//  NSDate+JSONString.m
//  iORM
//
//  Created by Maxime Guilbot on 7/26/12.
//  Copyright (c) 2012 Ekohe. All rights reserved.
//

#import "NSDate+JSONString.h"

@implementation NSDate (JSONString)

+(NSDate*) dateFromJSON:(NSString*)JSONdate {
    if (JSONdate == (NSString*)[NSNull null]) {
        return nil;
    }
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ssZZZZ"];
    return [df dateFromString:[[JSONdate stringByReplacingOccurrencesOfString:@"T" withString:@" "] stringByReplacingOccurrencesOfString:@"Z" withString:@"+0000"]];
}

-(NSString*) jsonString {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ssZZZZ"];
    NSString *jsonString = [df stringFromDate:self];
    return jsonString;
}

@end
