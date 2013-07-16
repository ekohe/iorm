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
+(NSArray*) singularRelations;

+(NSString*) indexPath;
+(NSString*) createPath;
-(NSString*) fetchManyRelationPath:(NSString*)relation;
-(NSString*) fetchRelationPath:(NSString*)relation;
+(Class) classForManyRelation:(NSString*)relation;
+(Class) classForRelation:(NSString*)relation;
+(Class) getFieldClass:(NSString*)field;
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

+(void) find:(NSString*)id success:(void (^)(Model* object))success failure:(void (^)(NSError* error))failure {
    Model *object = [[self alloc] init];
    object.id = id;
    [self findWithURI:[object path] success:success failure:failure];
}

+(void) findWithURI:(NSString*)uri success:(void (^)(Model* object))success failure:(void (^)(NSError* error))failure {
    [[self sharedClient] getPath:uri
                      parameters:nil
                         success:^(AFHTTPRequestOperation *operation, id responseObject) {
                             if ([responseObject isKindOfClass:[NSDictionary class]]) {
                                 NSDictionary *objectAttributes = (NSDictionary*)responseObject;
                                 
                                 Model *object = [[self alloc] init];
                                 [object updateAttributes:objectAttributes];                                 
                                 success(object);
                             }
                         }
                         failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                             failure(error);
                         }];
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
    
    [[[self class] sharedClient] getPath:[self fetchRelationPath:relation]
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

-(void) fetch:(NSString*)relation success:(void (^)(void))success failure:(void (^)(NSError* error))failure {
    if (![self persistent]) { failure(nil); return;}  // TODO: create a NSError object
    
    NSString *relationPropertyName = [relation camelizeWithLowerFirstLetter];
    if (![self respondsToSelector:NSSelectorFromString(relationPropertyName)]) {
        failure(nil); // TODO: create a NSError object
        NSLog(@"[%@] Error: couldn't find property %@ for relation %@", [[self class] description], relationPropertyName, relationPropertyName);
        return;
    }
    
    [[[self class] sharedClient] getPath:[self fetchRelationPath:relation]
                              parameters:nil
                                 success:^(AFHTTPRequestOperation *operation, id responseObject) {
                                     if ([responseObject isKindOfClass:[NSDictionary class]]) {
                                         
                                         Class relationKlass = [[self class] classForRelation:relation];
                                         Model *object = [[relationKlass alloc] init];
                                         [object updateAttributes:(NSDictionary*)responseObject];
                                         
                                         [self setValue:object forKey:relationPropertyName];
                                         
                                         success();
                                     } else if (responseObject==nil) {
                                         // There is no object for the relation
                                         [self setValue:nil forKey:relationPropertyName];
                                         success();
                                     } else {
                                         failure(nil);  // TODO: create a NSError object
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

-(void) hide:(UIViewController*)viewController prefix:(NSString*)prefix {    
    for (NSString *field in [[self class] fields]) {
        NSString *selectorString;
        if (prefix) {
            selectorString = [NSString stringWithFormat:@"%@_%@Label", prefix, field];
        } else {
            selectorString = [NSString stringWithFormat:@"%@Label", field];
        }
        
        if ([viewController respondsToSelector:NSSelectorFromString(selectorString)]) {
            UILabel *label = [viewController valueForKey:selectorString];
            label.hidden = YES;
        }
    }
    
    for (NSString *relation in [[self class] singularRelations]) {
        Model *relationObject = (Model*)[self valueForKey:relation];
        if (relationObject) {
            NSString *newPrefix;
            if (prefix) {
                newPrefix = [NSString stringWithFormat:@"%@_%@", prefix, relation];
            } else {
                newPrefix = relation;
            }
            [relationObject render:viewController prefix:newPrefix];
        }
    }
}

-(void) hide:(UIViewController*)viewController {
    [self hide:viewController prefix:nil];
}

-(void) render:(UIViewController*)viewController prefix:(NSString*)prefix {    
    for (NSString *field in [[self class] fields]) {
        NSString *selectorString;
        if (prefix) {
            selectorString = [NSString stringWithFormat:@"%@_%@Label", prefix, field];
        } else {
            selectorString = [NSString stringWithFormat:@"%@Label", field];
        }

        if ([viewController respondsToSelector:NSSelectorFromString(selectorString)]) {
            UILabel *label = [viewController valueForKey:selectorString];
            NSObject *value = [self valueForKey:field];
            if ((value) && (value != (NSObject*)[NSNull null])) {
                label.text = [NSString stringWithFormat:@"%@", value];
            } else {
                label.text = @"";
            }
            label.hidden = NO;
        }
    }
    
    for (NSString *relation in [[self class] singularRelations]) {
        Model *relationObject = (Model*)[self valueForKey:relation];
        if (relationObject) {
            NSString *newPrefix;
            if (prefix) {
                newPrefix = [NSString stringWithFormat:@"%@_%@", prefix, relation];
            } else {
                newPrefix = relation;
            }
            [relationObject render:viewController prefix:newPrefix];
        }
    }
}

-(void) render:(UIViewController*)viewController {
    [self render:viewController prefix:nil];
}

-(void) fillForm:(UIViewController*)viewController prefix:(NSString*)prefix {
    NSArray *fields = [[self class] fields];
    
    for (NSString *field in fields) {
        NSString *selectorString;
        if (prefix) {
            selectorString = [NSString stringWithFormat:@"%@_%@Field", prefix, field];
        } else {
            selectorString = [NSString stringWithFormat:@"%@Field", field];
        }
        if ([viewController respondsToSelector:NSSelectorFromString(selectorString)]) {
            UITextField *textfield = [viewController valueForKey:selectorString];
            if ([self valueForKey:field]) {
                NSLog(@"value field %@ - %@", [self valueForKey:field], [[self valueForKey:field] class]);
                if ([[self valueForKey:field] isKindOfClass:[NSDate class]]) {
                    textfield.text = [(NSDate*)[self valueForKey:field] jsonString];
                } else {
                    textfield.text = [NSString stringWithFormat:@"%@", [self valueForKey:field]];
                }
            }
        }
    }
    
    for (NSString *relation in [[self class] singularRelations]) {
        Model *relationObject = (Model*)[self valueForKey:relation];
        if (relationObject) {
            NSString *newPrefix;
            if (prefix) {
                newPrefix = [NSString stringWithFormat:@"%@_%@", prefix, relation];
            } else {
                newPrefix = relation;
            }
            [relationObject fillForm:viewController prefix:newPrefix];
        }
    }
}

-(void) fillForm:(UIViewController*)viewController {
    [self fillForm:viewController prefix:nil];
}

-(void) setValueFromControl:(NSObject*)control forField:(NSString*)field {
    
    if ([control isKindOfClass:[UITextField class]]) {
        UITextField *textfield = (UITextField*)control;
        NSString *stringValue = textfield.text;
        Class fieldClass = [[self class] getFieldClass:field];
        if (fieldClass == [NSString class]) {
            [self setValue:stringValue forKey:field];
#ifdef DEBUG
            NSLog(@"[%@] > Set %@ to \"%@\"", [[self class] description], stringValue, field);
#endif
            return;
        }
        if (fieldClass == [NSNumber class]) {
            // Assuming double type here..
            [self setValue:[NSNumber numberWithDouble:[stringValue doubleValue]] forKey:field];
            return;
        }
        if (fieldClass == [NSDate class]) {
            NSDate *date = [NSDate dateFromJSON:stringValue];
            [self setValue:date forKey:field];
            return;
        }
        NSLog(@"[%@] Warning: field class %@ not supported for field %@", [[self class] description], fieldClass, field);
        return;
    }

    NSLog(@"[%@] Warning: control %@ not supported for field %@", [[self class] description], control, field);

    // TODO: support more types and controls
}

-(Model*) updateFromForm:(UIViewController*)viewController prefix:(NSString*)prefix {
    Model *objectToUpdate = [self duplicate];
    NSArray *fields = [[self class] fields];
    for (NSString *field in fields) {
        NSString *selectorString;
        if (prefix) {
            selectorString = [NSString stringWithFormat:@"%@_%@Field", prefix, field];
        } else {
            selectorString = [NSString stringWithFormat:@"%@Field", field];
        }
        if ([viewController respondsToSelector:NSSelectorFromString(selectorString)]) {
            NSObject *control = [viewController valueForKey:selectorString];
            [objectToUpdate setValueFromControl:control forField:field];
        }
    }
    
    for (NSString *relation in [[self class] singularRelations]) {
        Model *relationObject = (Model*)[self valueForKey:relation];
        Class relationKlass = [[self class] classForRelation:[relation underscore]];
        NSString *newPrefix;
        if (prefix) {
            newPrefix = [NSString stringWithFormat:@"%@_%@", prefix, relation];
        } else {
            newPrefix = relation;
        }
        if (relationObject==nil) {
            relationObject = [[relationKlass alloc] init];
            relationObject = [relationObject updateFromForm:viewController prefix:newPrefix];
            if ([[[relationObject attributes] allKeys] count]>0) {
                // only set newly created object if it got assigned attributes
                [objectToUpdate setValue:relationObject forKey:relation];
            }
        } else {
            relationObject = [relationObject updateFromForm:viewController prefix:newPrefix];
            [objectToUpdate setValue:relationObject forKey:relation];
        }
    }
    
    return objectToUpdate;
}

-(Model*) updateFromForm:(UIViewController*)viewController {
    return [self updateFromForm:viewController prefix:nil];
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

-(NSString*) fetchRelationPath:(NSString*)relation {
    return [NSString stringWithFormat:@"%@/%@", [self path], relation];
}

+(Class) classForManyRelation:(NSString*)relation {
    NSString *singular = [relation classify];
    return NSClassFromString(singular);
}

+(Class) classForRelation:(NSString*)relation {
    // consider grouping with classForManyRelation ?
    // should we get the type of the property instead ? like getFieldClass?
    return NSClassFromString([relation classify]);
}

+(NSString*) pluralizedName {
    return [[self singularName] pluralize];
}

+(NSString*) singularName {
    return [[[self description] underscore] lowercaseString];
}

-(NSDictionary*) attributesWithPrefix:(NSString*)prefix withinAttributes:(NSMutableDictionary*)attributes {
    NSMutableDictionary *objectAttributes = [NSMutableDictionary dictionary];
    
    if ([self persistent]) {
        [objectAttributes setObject:self.id forKey:@"id"];
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
            if ([self valueForKey:propertyName]==[NSNull null]) { continue; }
            if ([propertyType isEqualToString:@"NSString"] && [self valueForKey:propertyName]) {
                [objectAttributes setObject:[self valueForKey:propertyName] forKey:[propertyName underscore]];
            }
            if ([propertyType isEqualToString:@"NSMutableArray"] && [self valueForKey:propertyName]) {
                NSMutableArray *keys = [NSMutableArray array];
                for (Model *object in [self valueForKey:propertyName]) {
                    if ([object isKindOfClass:[Model class]] && [object persistent]) {
                        [keys addObject:object.id];
                    }
                }
                if ([keys count]>0) {
                    [objectAttributes setObject:keys forKey:[NSString stringWithFormat:@"%@_ids", [[propertyName underscore] singularize]]];
                }
            }
            
            if ([propertyType isEqualToString:@"NSDate"] && [self valueForKey:propertyName]) {
                NSDate *date = (NSDate*)[self valueForKey:propertyName];
                if ([date isKindOfClass:[NSDate class]]) {
                    [objectAttributes setObject:[date jsonString] forKey:[propertyName underscore]];
                }
            }
            
            if ([propertyType isEqualToString:@"NSNumber"] && [self valueForKey:propertyName]) {
                [objectAttributes setObject:[self valueForKey:propertyName] forKey:[propertyName underscore]];
            }
            
            if ([NSClassFromString(propertyType) isSubclassOfClass:[Model class]]) {
                Model *relationObject = (Model*)[self valueForKey:propertyName];
                if (relationObject) {
                    objectAttributes = [NSMutableDictionary dictionaryWithDictionary:[relationObject attributesWithPrefix:[propertyName underscore] withinAttributes:objectAttributes]];
                }
            }
            
            // TODO: Add support for other types
        }
    }
    free(properties);
    
    if ((attributes) && (prefix) && ([[objectAttributes allKeys] count]>0)) {
        [attributes setValue:objectAttributes forKey:prefix];
    } else {
        attributes = objectAttributes;
    }
    
    return [NSDictionary dictionaryWithDictionary:attributes];
}

-(NSDictionary*) attributes {
    return [self attributesWithPrefix:nil withinAttributes:nil];
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
            NSString *attributeString = [NSString stringWithUTF8String:attribute];
            attributeString = [attributeString substringFromIndex:3];
            attributeString = [attributeString substringToIndex:attributeString.length - 1];
            return [attributeString UTF8String];
        }
    }
    return "";
}

// Get property type for a given field name
+(Class) getFieldClass:(NSString*)field {
    unsigned int outCount, i;
    objc_property_t *properties = class_copyPropertyList([self class], &outCount);
    for (i = 0; i < outCount; i++) {
        objc_property_t property = properties[i];
        const char *propName = property_getName(property);
        NSString *propertyName = [NSString stringWithUTF8String:propName];
        if([propertyName isEqualToString:field]) {
            const char *propType = getPropertyType(property);
            NSString *propertyType = [NSString stringWithUTF8String:propType];
            return NSClassFromString(propertyType);
        }
    }
    free(properties);
    return nil;
}

+(NSArray*) fields {
    NSMutableArray *fields = [NSMutableArray arrayWithObject:@"id"];
    
    unsigned int outCount, i;
    objc_property_t *properties = class_copyPropertyList([self class], &outCount);
    for (i = 0; i < outCount; i++) {
        objc_property_t property = properties[i];
        const char *propName = property_getName(property);
        const char *propType = getPropertyType(property);
        NSString *propertyType = [NSString stringWithUTF8String:propType];
        if(propName) {
            if (![NSClassFromString(propertyType) isSubclassOfClass:[Model class]]) {
                [fields addObject:[NSString stringWithUTF8String:propName]];
            }
        }
    }
    free(properties);
    
    return [NSArray arrayWithArray:fields];
}

+(NSArray*) singularRelations {
    NSMutableArray *relations = [NSMutableArray array];
    
    unsigned int outCount, i;
    objc_property_t *properties = class_copyPropertyList([self class], &outCount);
    for (i = 0; i < outCount; i++) {
        objc_property_t property = properties[i];
        const char *propName = property_getName(property);
        const char *propType = getPropertyType(property);
        NSString *propertyType = [NSString stringWithUTF8String:propType];

        if(propName) {
            if ([NSClassFromString(propertyType) isSubclassOfClass:[Model class]]) {
                [relations addObject:[NSString stringWithUTF8String:propName]];
            }
        }
    }
    free(properties);
    
    return [NSArray arrayWithArray:relations];
}

+ (NSArray *)pluralRelations {
    NSMutableArray *relations = [NSMutableArray array];
 
    unsigned int outCount, i;
    objc_property_t *properties = class_copyPropertyList([self class], &outCount);
    for (i = 0; i < outCount; i++) {
        objc_property_t property = properties[i];
        NSString *propName = [NSString stringWithUTF8String:property_getName(property)];
        const char *propType = getPropertyType(property);
        NSString *propertyType = [NSString stringWithUTF8String:propType];
        
        if(propName) {
            if ([NSClassFromString([[propName underscore] classify]) isSubclassOfClass:[Model class]] && [propertyType isEqualToString:@"NSArray"]) {
                [relations addObject:propName];
            }
        }
    }
    free(properties);
    
    return [NSArray arrayWithArray:relations];
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
                    
                    Class fieldClass = [[self class] getFieldClass:field];
                    if ((fieldClass == [NSString class]) || (fieldClass == [NSNumber class])) {
                        [self setValue:[attributes valueForKey:key] forKey:field];
#ifdef DEBUG_MODEL_UNASSIGNED_ATTRIBUTES
                        assigned = YES;
#endif
                    }
                    if (fieldClass == [NSDate class]) {
                        NSDate *date = [NSDate dateFromJSON:[attributes valueForKey:key]];
                        [self setValue:date forKey:field];
#ifdef DEBUG_MODEL_UNASSIGNED_ATTRIBUTES
                        assigned = YES;
#endif
                    }
                }
            }
            
            NSArray *singularRelations = [[self class] singularRelations];
            for (NSString *relation in singularRelations) {
                if ([relation isEqualToString:camelCasedKey]) {
                    Class relationKlass = [[self class] classForRelation:[relation underscore]];
                    Model *relationObject = [[relationKlass alloc] init];
                    [relationObject updateAttributes:[attributes valueForKey:key]];
                    [self setValue:relationObject forKey:relation];
                    assigned = YES;
                }
            }
            
            NSArray *pluralRelations = [[self class] pluralRelations];
            for (NSString *relation in pluralRelations) {
                
                if ([relation isEqualToString:camelCasedKey] && [[attributes objectForKey:key] isKindOfClass:[NSArray class]]) {
                    NSArray *dataArray = [attributes objectForKey:key];
                    NSMutableArray *objectArray = [NSMutableArray array];
                    
                    for (NSDictionary *attribs in dataArray) {
                        Class relationKlass = [[self class] classForRelation:[[relation underscore] singularize]];
                        Model *relationObject = [[relationKlass alloc] init];
                        [relationObject updateAttributes:attribs];
                        [objectArray addObject:relationObject];
                    }
                    
                    [self setValue:[NSArray arrayWithArray:objectArray] forKey:relation];
                    assigned = YES;
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
