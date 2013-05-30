//
//  NSDate+JSONString.m
//  iORM
//
//  Created by Maxime Guilbot on 7/26/12.
//  Copyright (c) 2012 Ekohe. All rights reserved.
//

#import "NSDate+JSONString.h"
#import <objc/runtime.h>

static char const * const dateOnlyKey = "dateOnlyKey";

@implementation NSDate (JSONString)

@dynamic dateOnly;

- (BOOL)dateOnly {
    return [objc_getAssociatedObject(self, dateOnlyKey) boolValue];
}

- (void)setDateOnly:(BOOL)dateOnly {
    objc_setAssociatedObject(self, dateOnlyKey, [NSNumber numberWithBool:dateOnly], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+(NSDate*) dateFromJSON:(NSString*)JSONdate {
    if (JSONdate == (NSString*)[NSNull null]) {
        return nil;
    }
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    NSDate *date;
    if ([JSONdate length]==10) {
        [df setDateFormat:@"yyyy-MM-dd"];
        date = [df dateFromString:JSONdate];
        date.dateOnly = YES;
    } else {
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ssZZZZ"];
        date = [df dateFromString:[[JSONdate stringByReplacingOccurrencesOfString:@"T" withString:@" "] stringByReplacingOccurrencesOfString:@"Z" withString:@"+0000"]];
        date.dateOnly = NO;
    }
    return date;
}

-(NSString*) jsonString {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    if (self.dateOnly) {
        [df setDateFormat:@"yyyy-MM-dd"];
    } else {
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ssZZZZ"];
    }
    NSString *jsonString = [df stringFromDate:self];
    return jsonString;
}

@end
