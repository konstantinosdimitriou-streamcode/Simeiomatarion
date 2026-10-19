#import "MacroStore.h"

@implementation MacroStep
@end

@implementation MacroStore {
	NSMutableArray<MacroStep *> *_steps;
	NSMutableDictionary<NSString *, NSArray<MacroStep *> *> *_saved;
	BOOL _recording;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_steps = [NSMutableArray array];
		_saved = [NSMutableDictionary dictionary];
	}
	return self;
}

- (BOOL)recording {
	return _recording;
}

- (NSArray<MacroStep *> *)steps {
	return _steps;
}

- (void)start {
	[_steps removeAllObjects];
	_recording = YES;
}

- (void)stop {
	_recording = NO;
}

- (void)addInsert:(NSString *)text at:(NSInteger)position {
	if (!_recording || text.length == 0) {
		return;
	}
	MacroStep *step = [MacroStep new];
	step.insert = YES;
	step.position = position;
	step.text = text;
	[_steps addObject:step];
}

- (void)addDelete:(NSString *)text at:(NSInteger)position {
	if (!_recording || text.length == 0) {
		return;
	}
	MacroStep *step = [MacroStep new];
	step.insert = NO;
	step.position = position;
	step.text = text;
	[_steps addObject:step];
}

- (NSDictionary *)jsonForStep:(MacroStep *)step {
	return @{
		@"op": step.insert ? @"insert" : @"delete",
		@"position": @(step.position),
		@"text": step.text ?: @""
	};
}

- (MacroStep *)stepFromJSON:(NSDictionary *)item {
	MacroStep *step = [MacroStep new];
	step.insert = [item[@"op"] isEqualToString:@"insert"];
	step.position = [item[@"position"] integerValue];
	step.text = item[@"text"] ?: @"";
	return step;
}

- (NSArray *)jsonForSteps:(NSArray<MacroStep *> *)steps {
	NSMutableArray *payload = [NSMutableArray array];
	for (MacroStep *step in steps) {
		[payload addObject:[self jsonForStep:step]];
	}
	return payload;
}

- (NSArray<MacroStep *> *)stepsFromJSON:(NSArray *)items {
	NSMutableArray<MacroStep *> *steps = [NSMutableArray array];
	for (id item in items) {
		if ([item isKindOfClass:[NSDictionary class]]) {
			[steps addObject:[self stepFromJSON:item]];
		}
	}
	return steps;
}

- (NSArray<NSString *> *)savedNames {
	return [_saved.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)rememberCurrentAs:(NSString *)name {
	if (name.length == 0) {
		return;
	}
	_saved[name] = [_steps copy];
}

- (BOOL)activateSaved:(NSString *)name {
	NSArray<MacroStep *> *steps = _saved[name];
	if (!steps) {
		return NO;
	}
	[_steps setArray:steps];
	return YES;
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
	NSMutableDictionary *saved = [NSMutableDictionary dictionary];
	for (NSString *name in _saved) {
		saved[name] = [self jsonForSteps:_saved[name]];
	}
	NSDictionary *payload = @{
		@"current": [self jsonForSteps:_steps],
		@"saved": saved
	};
	NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:error];
	if (!data) {
		return NO;
	}
	return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (BOOL)loadFromURL:(NSURL *)url error:(NSError **)error {
	NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
	if (!data) {
		return NO;
	}
	id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
	[_steps removeAllObjects];
	[_saved removeAllObjects];
	if ([object isKindOfClass:[NSArray class]]) {
		[_steps addObjectsFromArray:[self stepsFromJSON:object]];
		return YES;
	}
	if (![object isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	NSDictionary *payload = object;
	if ([payload[@"current"] isKindOfClass:[NSArray class]]) {
		[_steps addObjectsFromArray:[self stepsFromJSON:payload[@"current"]]];
	}
	if ([payload[@"saved"] isKindOfClass:[NSDictionary class]]) {
		for (NSString *name in payload[@"saved"]) {
			id steps = payload[@"saved"][name];
			if ([steps isKindOfClass:[NSArray class]]) {
				_saved[name] = [self stepsFromJSON:steps];
			}
		}
	}
	return YES;
}

@end
