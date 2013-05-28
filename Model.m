//
//  Model.m
//  iORM
//
//  Created by Maxime Guilbot on 7/12/12.
//  Copyright (c) 2012 Ekohe. All rights reserved.
//

#import "Model.h"
#import "objc/runtime.h"
#import "AFHTTPRequestOperation.h"
#import "AFJSONRequestOperation.h"
#import "NSString+Inflections.h"
#import "NSDate+JSONString.h"

#define DEBUG_MODEL
#define DEBUG_MODEL_UNASSIGNED_ATTRIBUTES

#ifndef BASE_URL
static NSString *baseUrl = @"http://localhost:3000";
#else
static NSString *baseUrl = BASE_URL;
#endif

static NSString *userAgent = nil;
static NSString *authorizationToken = nil;

@interface Model (PrivateMethods)
+(NSString*) pluralizedName;
+(NSString*) singularName;
+(NSArray*) fields;

+(NSString*) indexPath;
+(NSString*) createPath;
-(NSString*) fetchManyRelationPath:(NSString*)relation;
+(Class) classForManyRelation:(NSString*)relation;
@end

@implementation Model

-(id) init {
    self = [super init];
    if (self) {
        _id = nil;
    }
    return self;
}

+ (AFHTTPClient*)sharedClient {
    static id _sharedClient = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedClient = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:baseUrl]];
        [_sharedClient setDefaultHeader:@"Accept" value:@"application/json"];
        [_sharedClient setDefaultHeader:@"User-Agent" value:[self userAgent]];
        [_sharedClient registerHTTPOperationClass:[AFJSONRequestOperation class]];
        [_sharedClient setAuthorizationHeaderWithToken:authorizationToken];
    });
    
    return _sharedClient;
}

+ (NSString *)userAgent
{
    if (userAgent == nil) {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        NSString *version = [info objectForKey:@"CFBundleShortVersionString"];
        NSString *bundleName = [info objectForKey:@"CFBundleName"];
        userAgent = [NSString stringWithFormat:@"%@/%@", bundleName, version];
    }
    
    return userAgent;
}

+ (void) setAuthorizationToken:(NSString*)_authorizationToken {
    authorizationToken = _authorizationToken;
}


+(void) all:(void (^)(NSArray* objects))success failure:(void (^)(NSError* error))failure {
    [self allWithParameters:nil success:success failure:failure];
}


+(void) allWithParameters:(NSDictionary*)parameters success:(void (^)(NSArray* objects))success failure:(void (^)(NSError* error))failure {
    [[self sharedClient] getPath:[self indexPath]
                      parameters:parameters
                         success:^(AFHTTPRequestOperation *operation, id responseObject) {
                             if ([responseObject isKindOfClass:[NSArray class]]) {
                                 NSArray *objectsAttributes = (NSArray*)responseObject;
                                 NSMutableArray *objects = [NSMutableArray array];
                                 
                                 for (NSDictionary *attributes in objectsAttributes) {
                                     Model *object = [[self alloc] init];
                                     [object updateAttributes:attributes];
                                     [objects addObject:object];
                                 }
                                 
                                 success(objects);
                             }

                         }
                         failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                             failure(error);
                         }];
}

-(void) create:(void (^)(void))success failure:(void (^)(void))failure {
    [self postTo:[[self class] createPath] success:success failure:failure];
}

-(void) postTo:(NSString*)path success:(void (^)(void))success failure:(void (^)(void))failure {
    NSDictionary *_attributes = [NSDictionary dictionaryWithObject:[self attributes] forKey:[[self class] singularName]];
    [self postTo:path attributes:_attributes success:success failure:failure];
}

-(void) postTo:(NSString*)path attributes:(NSDictionary*)_attributes success:(void (^)(void))success failure:(void (^)(void))failure {
#ifdef DEBUG_MODEL
    NSLog(@"[%@] > POST to path %@ with attributes: %@", [[self class] description], path, _attributes);
#endif
    [[[self class] sharedClient] postPath:path
                               parameters:_attributes
                                  success:^(AFHTTPRequestOperation *operation, id responseObject) {
#ifdef DEBUG_MODEL
                                      NSLog(@"[%@] < POST response: %@", [[self class] description], responseObject);
#endif
                                      if ([responseObject isKindOfClass:[NSDictionary class]]) {
                                          [self updateAttributes:(NSDictionary*)responseObject];
                                      }
                                      
                                      success();
                                  }
                                  failure:^(AFHTTPRequestOperation *operation, NSError *error) {
#ifdef DEBUG_MODEL
                                      NSLog(@"[%@] < POST Failure status code %d, response: %@", [[self class] description], [operation.response statusCode], operation.responseString);
#endif
                                      // Unprocessable Entity - The object has validation errors
                                      if ([operation.response statusCode]==422) {
                                          if ([operation isKindOfClass:[AFJSONRequestOperation class]]) {
                                              AFJSONRequestOperation *jsonOperation = (AFJSONRequestOperation*)operation;
                                              NSDictionary *errorResponse = jsonOperation.responseJSON;
                                              if ([errorResponse isKindOfClass:[NSDictionary class]]) {
                                                  errors = [errorResponse valueForKey:@"errors"];
                                              }
                                          }
                                      }
                                      failure();
                                  }];
    
}

-(void) save:(void (^)(void))success failure:(void (^)(NSError* error))failure {
    NSMutableDictionary *_rawAttributes = [NSMutableDictionary dictionaryWithDictionary:[self attributes]];
    
    // id is a protected attribute
    [_rawAttributes removeObjectForKey:@"id"];
    
    NSDictionary *_attributes = [NSDictionary dictionaryWithObject:_rawAttributes forKey:[[self class] singularName]];
    
#ifdef DEBUG_MODEL
    NSLog(@"[%@] > PUT to path %@ with attributes: %@", [[self class] description], [self path], _attributes);
#endif
    
    [[[self class] sharedClient] putPath:[self path]
                              parameters:_attributes
                                 success:^(AFHTTPRequestOperation *operation, id responseObject) {
#ifdef DEBUG_MODEL
                                      NSLog(@"[%@] < PUT response: %@", [[self class] description], responseObject);
#endif
                                      if ([responseObject isKindOfClass:[NSDictionary class]]) {
                                          [self updateAttributes:(NSDictionary*)responseObject];
                                      }
                                      
                                      success();
                                  }
                                 failure:^(AFHTTPRequestOperation *operation, NSError *error) {
#ifdef DEBUG_MODEL
                                      NSLog(@"[%@] < PUT Failure status code %d, response: %@", [[self class] description], [operation.response statusCode], operation.responseString);
#endif
                                      // Unprocessable Entity - The object has validation errors
                                      // TODO: factor this case
                                      if ([operation.response statusCode]==422) {
                                          if ([operation isKindOfClass:[AFJSONRequestOperation class]]) {
                                              AFJSONRequestOperation *jsonOperation = (AFJSONRequestOperation*)operation;
                                              NSDictionary *errorResponse = jsonOperation.responseJSON;
                                              if ([errorResponse isKindOfClass:[NSDictionary class]]) {
                                                  errors = [errorResponse valueForKey:@"errors"];
                                              }
                                          }
                                      }
                                      failure(error);
                                  }];

}

-(void) destroy:(void (^)(void))success failure:(void (^)(NSError* error))failure {
#ifdef DEBUG_MODEL
    NSLog(@"[%@] > DELETE to path %@", [[self class] description], [self path]);
#endif
    
    [[[self class] sharedClient] deletePath:[self path]
                              parameters:nil
                                 success:^(AFHTTPRequestOperation *operation, id responseObject) {
#ifdef DEBUG_MODEL
                                     NSLog(@"[%@] < DELETE response: %@", [[self class] description], responseObject);
#endif
                                     
                                     success();
                                 }
                                 failure:^(AFHTTPRequestOperation *operation, NSError *error) {
#ifdef DEBUG_MODEL
                                     NSLog(@"[%@] < DELETE Failure status code %d, response: %@", [[self class] description], [operation.response statusCode], operation.responseString);
#endif
                                     failure(error);
                                 }];
}

-(void) fetchMany:(NSString*)relation success:(void (^)(void))success failure:(void (^)(NSError* error))failure {
    if (![self persistent]) { failure(nil); return;}  // TODO: create a NSError object
    
    [[[self class] sharedClient] getPath:[self fetchManyRelationPath:relation]
                      parameters:nil
                         success:^(AFHTTPRequestOperation *operation, id responseObject) {
                             if ([responseObject isKindOfClass:[NSArray class]]) {
                                 NSArray *objectsAttributes = (NSArray*)responseObject;
                                 NSMutableArray *objects = [NSMutableArray array];
                                 
                                 Class relationKlass = [[self class] classForManyRelation:relation];
                                 for (NSDictionary *attributes in objectsAttributes) {
                                     if (relationKlass==nil) {
                                         NSLog(@"Can't find class for relation %@", relation);
                                     } else {
                                         Model *object = [[relationKlass alloc] init];
                                         [object updateAttributes:attributes];
                                         [objects addObject:object];
                                     }
                                 }
                                 
                                 [self setValue:objects forKey:relation];
                                 success();
                             } else {
                                 failure(nil); // TODO: create a NSError object
                             }
                         }
                         failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                             failure(error);
                         }];

}

-(void) push:(Model*)object to:(NSString*)relation success:(void (^)(void))success failure:(void (^)(NSError* error))failure {
    
    NSDictionary *_attributes = [NSDictionary dictionaryWithObject:[object attributes] forKey:[[object class] singularName]];

    if (![self persistent]) { failure(nil); return;} // Should return an NSError object as well

#ifdef DEBUG_MODEL
    NSLog(@"[%@] > POST to path %@ with attributes: %@", [[self class] description], [self path], _attributes);
#endif
    
    NSMutableArray *relationArray = [self valueForKey:relation];
    if (relationArray==nil) {
        relationArray = [NSMutableArray arrayWithCapacity:1];
        [self setValue:relationArray forKey:relation];
    }
    if ([relationArray isKindOfClass:[NSMutableArray class]]) {
        [relationArray addObject:object];
    } else {
        NSLog(@"[%@] Warning: object %@ not pushed into relation %@", [[self class] description], object, relation);
    }
    
    [[[self class] sharedClient] postPath:[self fetchManyRelationPath:relation]
                              parameters:_attributes
                                 success:^(AFHTTPRequestOperation *operation, id responseObject) {
#ifdef DEBUG_MODEL
                                     NSLog(@"[%@] < POST response: %@", [[self class] description], responseObject);
#endif
                                     if ([responseObject isKindOfClass:[NSDictionary class]]) {
                                         [object updateAttributes:(NSDictionary*)responseObject];
                                     }
                                     
                                     success();
                                 }
                                 failure:^(AFHTTPRequestOperation *operation, NSError *error) {
#ifdef DEBUG_MODEL
                                     NSLog(@"[%@] < POST Failure status code %d, response: %@", [[self class] description], [operation.response statusCode], operation.responseString);
#endif
                                     // Unprocessable Entity - The object has validation errors
                                     if ([operation.response statusCode]==422) {
                                         if ([operation isKindOfClass:[AFJSONRequestOperation class]]) {
                                             AFJSONRequestOperation *jsonOperation = (AFJSONRequestOperation*)operation;
                                             NSDictionary *errorResponse = jsonOperation.responseJSON;
                                             if ([errorResponse isKindOfClass:[NSDictionary class]]) {
                                                 errors = [errorResponse valueForKey:@"errors"];
                                             }
                                         }
                                     }
                                     failure(error);
                                 }];

}

#pragma mark - State

-(BOOL) persistent {
    return (_id!=nil);
}

#pragma mark - Errors

-(NSDictionary*) errors {
    return errors;
}

-(BOOL) hasErrors {
    return ([[errors allKeys] count]>0);
}

-(NSString*) errorMessage {
    if (![self hasErrors]) { return nil; }
    NSMutableArray *messages = [NSMutableArray array];
    
    for (NSString *key in [self.errors allKeys]) {
        NSObject *_errors = [self.errors objectForKey:key];
        NSString *message;
        if ([_errors isKindOfClass:[NSArray class]]) {
            message = [(NSArray*)_errors componentsJoinedByString:@", "];
        }
        if ([_errors isKindOfClass:[NSString class]]) {
            message = (NSString*)_errors;
        }

        if ([key isEqualToString:@"base"]) {
            [messages addObject:message];
        } else {
            [messages addObject:[NSString stringWithFormat:@"%@ %@", [key capitalizedString], message]];
        }
    }
    
    return [messages componentsJoinedByString:@", "];
}

#pragma mark - Misc.

-(Model*) duplicate {
    Model* newObject = [[[self class] alloc] init];
    [newObject updateAttributes:[self attributes]];
    return newObject;
}

#pragma mark - Rendering

-(void) render:(UIViewController*)viewController {
    NSArray *fields = [[self class] fields];

    for (NSString *field in fields) {
        NSString *selectorString = [NSString stringWithFormat:@"%@Label", field];
        if ([viewController respondsToSelector:NSSelectorFromString(selectorString)]) {
            UILabel *label = [viewController valueForKey:selectorString];
            label.text = [self valueForKey:field];
        }
    }
}

-(void) fillForm:(UIViewController*)viewController {
    NSArray *fields = [[self class] fields];
    
    for (NSString *field in fields) {
        NSString *selectorString = [NSString stringWithFormat:@"%@Field", field];
        if ([viewController respondsToSelector:NSSelectorFromString(selectorString)]) {
            UITextField *textfield = [viewController valueForKey:selectorString];
            textfield.text = [self valueForKey:field];
        }
    }
}

-(Model*) updateFromForm:(UIViewController*)viewController {
    Model *objectToUpdate = [self duplicate];
    NSArray *fields = [[self class] fields];
    for (NSString *field in fields) {
        NSString *selectorString = [NSString stringWithFormat:@"%@Field", field];
        if ([viewController respondsToSelector:NSSelectorFromString(selectorString)]) {
            UITextField *textfield = [viewController valueForKey:selectorString];
            [objectToUpdate setValue:textfield.text forKey:field];
        }
    }
    return objectToUpdate;
}

#pragma mark - Private methods

+(NSString*) indexPath {
    return [NSString stringWithFormat:@"/%@", [self pluralizedName]];
}

+(NSString*) createPath {
    return [self indexPath];
}

-(NSString*) path {
    return [NSString stringWithFormat:@"/%@/%@", [[self class] pluralizedName], self.id];
}

-(NSString*) fetchManyRelationPath:(NSString*)relation {
    return [NSString stringWithFormat:@"%@/%@", [self path], relation];
}

+(Class) classForManyRelation:(NSString*)relation {
    NSString *singular = [relation classify];
    return NSClassFromString(singular);
}

+(NSString*) pluralizedName {
    return [[self singularName] pluralize];
}

+(NSString*) singularName {
    return [[[self description] underscore] lowercaseString];
}

-(NSDictionary*) attributes {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    
    if ([self persistent]) {
        [attributes setObject:self.id forKey:@"id"];
    }
    
    unsigned int outCount, i;
    objc_property_t *properties = class_copyPropertyList([self class], &outCount);
    for (i = 0; i < outCount; i++) {    
        objc_property_t property = properties[i];
        const char *propName = property_getName(property);
        if(propName) {
            const char *propType = getPropertyType(property);
            NSString *propertyName = [NSString stringWithUTF8String:propName];
            NSString *propertyType = [NSString stringWithUTF8String:propType];
            
            if ([propertyType isEqualToString:@"NSString"] && [self valueForKey:propertyName]) {
                [attributes setObject:[self valueForKey:propertyName] forKey:[propertyName underscore]];
            }
            
            if ([propertyType isEqualToString:@"NSMutableArray"] && [self valueForKey:propertyName]) {
                NSMutableArray *keys = [NSMutableArray array];
                for (Model *object in [self valueForKey:propertyName]) {
                    if ([object isKindOfClass:[Model class]] && [object persistent]) {
                        [keys addObject:object.id];
                    }
                }
                if ([keys count]>0) {
                    [attributes setObject:keys forKey:[NSString stringWithFormat:@"%@_ids", [[propertyName underscore] singularize]]];
                }
            }
            
            if ([propertyType isEqualToString:@"NSDate"] && [self valueForKey:propertyName]) {
                NSDate *date = (NSDate*)[self valueForKey:propertyName];
                if ([date isKindOfClass:[NSDate class]]) {
                    [attributes setObject:[date jsonString] forKey:[propertyName underscore]];
                }
            }

            if ([propertyType isEqualToString:@"NSNumber"] && [self valueForKey:propertyName]) {
                [attributes setObject:[self valueForKey:propertyName] forKey:[propertyName underscore]];
            }

            // TODO: Add support for other types - like what?
        }
    }
    free(properties);
    
    return [NSDictionary dictionaryWithDictionary:attributes];
}

-(BOOL) isEqualTo:(Model*)object {
    if ((![self.id isKindOfClass:[NSString class]]) || (![object.id isKindOfClass:[NSString class]])) {
        return NO;
    }
    return ([object isKindOfClass:[self class]] && [self.id isEqualToString:object.id]);
}

// Get property type for a given property
static const char * getPropertyType(objc_property_t property) {
    const char *attributes = property_getAttributes(property);
    char buffer[1 + strlen(attributes)];
    strcpy(buffer, attributes);
    char *state = buffer, *attribute;
    while ((attribute = strsep(&state, ",")) != NULL) {
        if (attribute[0] == 'T' && attribute[1] != '@') {
            // it's a C primitive type:
            /*
             if you want a list of what will be returned for these primitives, search online for
             "objective-c" "Property Attribute Description Examples"
             apple docs list plenty of examples of what you get for int "i", long "l", unsigned "I", struct, etc.
             */
            return (const char *)[[NSData dataWithBytes:(attribute + 1) length:strlen(attribute) - 1] bytes];
        }
        else if (attribute[0] == 'T' && attribute[1] == '@' && strlen(attribute) == 2) {
            // it's an ObjC id type:
            return "id";
        }
        else if (attribute[0] == 'T' && attribute[1] == '@') {
            // it's another ObjC object type:
            return (const char *)[[NSData dataWithBytes:(attribute + 3) length:strlen(attribute) - 4] bytes];
        }
    }
    return "";
}

+(NSArray*) fields {
    NSMutableArray *fields = [NSMutableArray arrayWithObject:@"id"];
    
    unsigned int outCount, i;
    objc_property_t *properties = class_copyPropertyList([self class], &outCount);
    for (i = 0; i < outCount; i++) {
        objc_property_t property = properties[i];
        const char *propName = property_getName(property);
        if(propName) {
            [fields addObject:[NSString stringWithUTF8String:propName]];
        }
    }
    free(properties);
    
    return [NSArray arrayWithArray:fields];
}

-(void) updateAttributes:(NSDictionary*)attributes {
    NSArray *fields = [[self class] fields];
    for (NSString *key in [attributes allKeys]) {
        
        if ([key isEqualToString:@"_id"] || [key isEqualToString:@"id"]) {
            self.id = [attributes valueForKey:key];
        } else {        
            NSString *camelCasedKey = [key camelizeWithLowerFirstLetter];
#ifdef DEBUG_MODEL_UNASSIGNED_ATTRIBUTES
            BOOL assigned = NO;
#endif
            for (NSString *field in fields) {
                if ([field isEqualToString:camelCasedKey]) {
                    [self setValue:[attributes valueForKey:key] forKey:field];
#ifdef DEBUG_MODEL_UNASSIGNED_ATTRIBUTES
                    assigned = YES;
#endif
                }
            }
#ifdef DEBUG_MODEL_UNASSIGNED_ATTRIBUTES
            if (!assigned) {
                NSLog(@"[%@] ! Unassigned attribute %@ - %@ - value: %@", [[self class] description], key, camelCasedKey, [attributes valueForKey:key]);
            }
#endif
        }
    }
}

@end
