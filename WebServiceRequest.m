//
//  WebServiceRequest.m
//
//  Created by Maxime Guilbot on 12/15/10.
//  Copyright 2010 ekohe. All rights reserved.
//

#import "WebServiceRequest.h"

@implementation WebServiceRequest

+(NSString*) endPoint {
	return @"http://your_own_webendpoint.com";
}

// - (void) jsonFinishedLoading:(NSDictionary*)json {
//  if (delegate==nil)
//    return;
//  
//  if (json==nil)
//    return [delegate jsonDidFailWithError:nil jsonRequest:self];
// 
//     // Badges are handled there so they can be sent by the back-end at any point
//  if (([json isKindOfClass:[NSDictionary class]]) &&
//         ([json valueForKey:@"new_badges"]!=nil) &&
//         ([json valueForKey:@"new_badges"]!=[NSNull null])) {
//         // Example
//     }
//     
//  if (([json isKindOfClass:[NSDictionary class]]) && ([json valueForKey:@"error"]!=nil)) {
//    NSString *error = [json valueForKey:@"error"];
//    if ([error isEqualToString:@"access_denied"]) {
//       // Do something
//    }
//    [delegate jsonDidFinishLoading:json jsonRequest:self];
//  } else {
//    [delegate jsonDidFinishLoading:json jsonRequest:self];
//  }
// }

@end
