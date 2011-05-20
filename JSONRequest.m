//
//  JsonRequest.m
//
//  Created by Maxime Guilbot on 6/4/10.
//  Copyright 2010 ekohe. All rights reserved.
//

#import "JSONRequest.h"
#import "Authorization.h"

@interface JSONRequest (PrivateMethods)
-(void) initiateRequest;
-(void) saveCookiesInResponse:(NSHTTPURLResponse*)response;
-(void) addCookiesToRequest:(NSMutableURLRequest*)request;
@end

@implementation JSONRequest

@synthesize path, delegate, temp, method, body, response, cookies;

+(NSString*) endPoint {
	return @"undefined";
}

+(NSString*) alterUrl:(NSString*)url {
	return url;
}

- (id) initGetWithPath:(NSString*)aPath delegate:(id<JSONRequestDelegate>)aDelegate {
	if (self = [super init])
	{
		self.path = [[self class] alterUrl:aPath];
		self.delegate = aDelegate;
		self.method = @"GET";
		self.body = nil;
		self.cookies = nil;
		[self initiateRequest];
	}
	
	return self;	
}

- (id) initPostWithPath:(NSString*)aPath httpBody:(NSString*)aBody delegate:(id<JSONRequestDelegate>)aDelegate {
	if (self = [super init])
	{
		self.path = [[self class] alterUrl:aPath];
		self.delegate = aDelegate;
		self.method = @"POST";
		self.body = aBody;
		self.cookies = nil;
		[self initiateRequest];
	}
	
	return self;
}

- (id) initPostWithPath:(NSString*)aPath httpBody:(NSString*)aBody cookie:(NSString*)aCookie delegate:(id<JSONRequestDelegate>)aDelegate {
	if (self = [super init])
	{
		self.path = [[self class] alterUrl:aPath];
		self.delegate = aDelegate;
		self.method = @"POST";
		self.body = aBody;
		self.cookies = [NSArray arrayWithObject:aCookie];
		[self initiateRequest];
	}
	
	return self;
}

- (id) initPostWithPath:(NSString*)aPath parameters:(NSDictionary*)params delegate:(id<JSONRequestDelegate>)aDelegate {
	NSMutableArray *bodyComponents = [NSMutableArray array];
	
	for (NSString *key in [params allKeys]) {
        if ([[params valueForKey:key] isKindOfClass:[NSString class]]) {
            [bodyComponents addObject:[NSString stringWithFormat:@"%@=%@", [key stringByUrlEncoding], [[params valueForKey:key] stringByUrlEncoding]]]; 
        } else if ([[params valueForKey:key] isKindOfClass:[NSArray class]]) {
            for (NSString* s in (NSArray*)[params valueForKey:key]) {
                [bodyComponents addObject:[NSString stringWithFormat:@"%@[]=%@", [key stringByUrlEncoding], [s stringByUrlEncoding]]]; 
            }
        } else {
			NSString *value = [NSString stringWithFormat:@"%@", [params valueForKey:key]];
            [bodyComponents addObject:[NSString stringWithFormat:@"%@=%@", [key stringByUrlEncoding], [value stringByUrlEncoding]]]; 
        }
    
	}
	
	return [self initPostWithPath:aPath httpBody:[bodyComponents componentsJoinedByString:@"&"] delegate:aDelegate];
}

#pragma mark -
#pragma mark Network Operations

-(void) initiateRequest {
	// Create URL from path and completeURL
	NSURL *url = [NSURL URLWithString:[[[self class] endPoint] stringByAppendingString:path]];

	// Create URL Request
	NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
	
	if (![method isEqualToString:@"GET"]) {
		[urlRequest setHTTPMethod:method];
		[urlRequest addValue:@"application/x-www-form-urlencoded" forHTTPHeaderField: @"Content-Type"];
		[urlRequest setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
	}

#ifdef DEBUG_NETWORK
	NSLog(@"[Network] Sending request: %@: %@", method, [url absoluteURL]);
#endif

    [self addCookiesToRequest:urlRequest];
		
	// Initiate request
	[NSURLConnection connectionWithRequest:urlRequest delegate:self];
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse {
    if (redirectResponse!=nil)
    {
#ifdef DEBUG_NETWORK
        NSLog(@"[Network] Redirection to request: %@ - redirectResponse: %@", request, redirectResponse);
#endif
        [self saveCookiesInResponse:(NSHTTPURLResponse*)redirectResponse];

        NSMutableURLRequest *newRequest = [NSMutableURLRequest requestWithURL:[request URL]];
        [self addCookiesToRequest:(NSMutableURLRequest*)newRequest];
        return newRequest;
    }
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)resp {
	if ([resp respondsToSelector:@selector(statusCode)])
		self.response = (NSHTTPURLResponse*)resp;

	// Initialize temporary data storage
	NSMutableData *data = [[NSMutableData alloc] init];
	self.temp = data;
	[data release];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	[temp appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	NSString *jsonString = [[NSString alloc] initWithData:temp encoding:NSUTF8StringEncoding];
    if (jsonString==nil) {
        jsonString = [[NSString alloc] initWithData:temp encoding:NSWindowsCP1252StringEncoding];
    }
#ifdef DEBUG_NETWORK
	NSLog(@"[Network] Got response: %@", jsonString);
#endif
	NSDictionary *jsonResults = [jsonString JSONValue];
		
    [self saveCookiesInResponse:self.response];
    
    [jsonString release];

	[self jsonFinishedLoading:jsonResults];
}

- (void) jsonFinishedLoading:(NSDictionary*)json {
	if (delegate!=nil) {
		if (json==nil) {
			[delegate jsonDidFailWithError:nil jsonRequest:self];
		} else {
			[delegate jsonDidFinishLoading:json jsonRequest:self];
		}
	}
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
#ifdef DEBUG_NETWORK
	NSLog(@"[Network] Failed with error %@", error);
#endif
	
	if ((error.domain == NSURLErrorDomain) && (error.code == -1009)) {
		[ErrorHUD displayErrorMessage:@"We can't connect to the internet right now.\nCheck your network or try again in a few minutes!"];
	}
     
	if (delegate!=nil)
		[delegate jsonDidFailWithError:error jsonRequest:self];
}

-(void) saveCookiesInResponse:(NSHTTPURLResponse*)resp {
    // Cookie handling
	if ([[[resp allHeaderFields] allKeys] indexOfObject:@"Set-Cookie"]!=NSNotFound) {
		NSString *received_cookies = [[resp allHeaderFields] objectForKey:@"Set-Cookie"];
        NSArray *receivedCookies = [received_cookies componentsSeparatedByString:@","];
        NSMutableArray *cookiesToSave = [NSMutableArray array];
        for (NSString *received_cookie in receivedCookies) {
            NSRange semicolon_range = [received_cookie rangeOfString:@";"];
            
            if (semicolon_range.location != NSNotFound) {
                NSString *strippedCookie = [received_cookie substringToIndex:semicolon_range.location];
#ifdef DEBUG_NETWORK_COOKIE
                NSLog(@"[Network] Save Cookie: %@", strippedCookie);
#endif			
                [cookiesToSave addObject:strippedCookie];
            }		
        }
        [Authorization setCookies:(NSArray*)cookiesToSave];
	} else {
#ifdef DEBUG_NETWORK_COOKIE
		NSLog(@"[Network] No Cookies found in headers: %@", [resp allHeaderFields]);
#endif			
	}
    
}

-(void) addCookiesToRequest:(NSMutableURLRequest*)request {
    if (self.cookies) {
        for (NSString *cookie in cookies) {
            [request addValue:cookie forHTTPHeaderField:@"Cookie"];
#ifdef DEBUG_NETWORK_COOKIE
            NSLog(@"[Network] With cookie: %@", cookie);
#endif
        }
	} else {
        for (NSString *cookie in [Authorization cookies]) {
			[request addValue:cookie forHTTPHeaderField:@"Cookie"];
#ifdef DEBUG_NETWORK_COOKIE
            NSLog(@"[Network] With cookie: %@", cookie);
#endif
        }
	}    
}

#pragma mark -
#pragma mark Memory Management

- (void) dealloc {
	[path release];
	[temp release];
	[method release];
	[body release];
	[response release];
	[cookies release];
 	[super dealloc];
}

@end
