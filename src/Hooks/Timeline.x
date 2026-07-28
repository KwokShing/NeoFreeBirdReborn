//
//  Timeline.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Timeline/BHTForYouKeywordFilter.h"

// MARK: - For You timeline identity

// X exposes both For You and Following through TIMELINE_HOME.  Never infer the
// selected feed from that display location, localized tab titles, or whichever
// tab happens to be visible.  Instead, carry the primary Home model's identity
// through its deserialized URT timeline and only filter the controller that
// owns that exact object.  Every unknown runtime shape deliberately fails open.
static char kBHTForYouTimelineRoleKey;
static char kBHTForYouKeywordDecisionKey;

typedef NS_ENUM(NSInteger, BHTHomeTimelineRole) {
    BHTHomeTimelineRoleNonForYou = 0,
    BHTHomeTimelineRolePrimaryForYou = 1,
    BHTHomeTimelineRoleAmbiguous = 2,
};

static void BHTMergeHomeTimelineRole(id timeline,
                                     BHTHomeTimelineRole incomingRole) {
    if (!timeline) return;
    @synchronized(timeline) {
        NSNumber* existing =
            objc_getAssociatedObject(timeline,
                                     &kBHTForYouTimelineRoleKey);
        BHTHomeTimelineRole mergedRole = incomingRole;
        if (existing &&
            existing.integerValue != (NSInteger)incomingRole) {
            // A model/stream observed in both roles is not safe to filter.
            // Preserve that ambiguity permanently rather than letting the
            // last factory call win.
            mergedRole = BHTHomeTimelineRoleAmbiguous;
        }
        objc_setAssociatedObject(timeline, &kBHTForYouTimelineRoleKey,
                                 @(mergedRole),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static NSNumber* BHTHomeTimelineRoleForTimeline(id timeline) {
    return timeline
               ? objc_getAssociatedObject(timeline,
                                          &kBHTForYouTimelineRoleKey)
               : nil;
}

// T1TimelineFactory names each model before it is handed to the segmented Home
// controller.  Marking both the getters and the final root-factory arguments
// covers cached and cold construction without guessing from view state.
%group BHTForYouTimelineProvenance

%hook T1TimelineFactory

- (id)homeTimelineForAccount:(id)account {
    id timeline = %orig;
    BHTMergeHomeTimelineRole(timeline,
                             BHTHomeTimelineRolePrimaryForYou);
    return timeline;
}

- (id)homeCountryFilteredTimelineForAccount:(id)account {
    id timeline = %orig;
    BHTMergeHomeTimelineRole(timeline,
                             BHTHomeTimelineRoleNonForYou);
    return timeline;
}

- (id)homeTopicFilteredTimelineForAccount:(id)account {
    id timeline = %orig;
    BHTMergeHomeTimelineRole(timeline,
                             BHTHomeTimelineRoleNonForYou);
    return timeline;
}

- (id)homeLatestTimelineForAccount:(id)account {
    id timeline = %orig;
    BHTMergeHomeTimelineRole(timeline,
                             BHTHomeTimelineRoleNonForYou);
    return timeline;
}

- (id)homeRankedFollowingTimelineForAccount:(id)account {
    id timeline = %orig;
    BHTMergeHomeTimelineRole(timeline,
                             BHTHomeTimelineRoleNonForYou);
    return timeline;
}

- (id)rootViewControllerForHomeTimeline:(id)homeTimeline
            homeCountryFilteredTimeline:(id)homeCountryFilteredTimeline
                     homeLatestTimeline:(id)homeLatestTimeline
            homeRankedFollowingTimeline:(id)homeRankedFollowingTimeline
                                account:(id)account {
    BHTMergeHomeTimelineRole(homeTimeline,
                             BHTHomeTimelineRolePrimaryForYou);
    BHTMergeHomeTimelineRole(homeCountryFilteredTimeline,
                             BHTHomeTimelineRoleNonForYou);
    BHTMergeHomeTimelineRole(homeLatestTimeline,
                             BHTHomeTimelineRoleNonForYou);
    BHTMergeHomeTimelineRole(homeRankedFollowingTimeline,
                             BHTHomeTimelineRoleNonForYou);
    return %orig;
}

%end

// TFNTwitterHomeTimeline converts the model above into the immutable URT
// timeline stored by T1URTViewController.  Propagate the explicit role across
// that boundary; a missing role stays missing rather than becoming For You.
%hook TFNTwitterHomeTimeline

- (id)deserializeStream {
    id timeline = %orig;
    NSNumber* role = BHTHomeTimelineRoleForTimeline(self);
    if (timeline && role) {
        BHTMergeHomeTimelineRole(
            timeline, (BHTHomeTimelineRole)role.integerValue);
    }
    return timeline;
}

%end

%end

// MARK: - Hide custom timelines

static __weak NSObject* PinnedTimelinesRepository;
static NSArray* LastPinnedTimelineModels;
static BOOL PinnedTimelinesWriteBypass = NO;

// Applies a toggle without relaunching. Hiding rewrites the UNCHANGED pinned
// list purely to republish — updatePinnedTimelines: persists server-side, so
// anything else would unpin for real; the delegate hook below swaps in the
// empty list on the way through.
void applyHideCustomTimelinesSetting(void) {
    NSObject* repository = PinnedTimelinesRepository;
    if (!repository) {
        return;
    }

    if ([BHTSettings boolForKey:@"hide_custom_timelines"]) {
        NSArray* models = LastPinnedTimelineModels;
        if (models.count > 0) {
            PinnedTimelinesWriteBypass = YES;
            ((void (*)(id, SEL, id))objc_msgSend)(repository, @selector(updatePinnedTimelines:), models);
            PinnedTimelinesWriteBypass = NO;
        }
    } else if ([repository respondsToSelector:@selector(fetchPinnedTimelinesWithThrottleEnabled:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            repository, @selector(fetchPinnedTimelinesWithThrottleEnabled:), NO);
    }
}

// The trailing accessory is only reconfigured while the strip is showing, so a
// button built before hiding mid-session survives; sync its visibility here. The
// property is a Swift lazy var whose storage ivar KVC can't see, hence the fallback.
static void SyncHomeAddTabButton(id container, BOOL hidden) {
    UIView* button = nil;

    @try {
        button = [container valueForKey:@"addTabButton"];
    } @catch (__unused NSException* exception) {
        unsigned int ivarCount = 0;
        Ivar* ivars = class_copyIvarList([container class], &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char* name = ivar_getName(ivars[i]);
            if (name && strstr(name, "addTabButton")) {
                button = object_getIvar(container, ivars[i]);
                break;
            }
        }
        free(ivars);
    }

    if ([button isKindOfClass:[UIView class]]) {
        button.hidden = hidden;
    }
}

// The repository publishes the pinned list through this single delegate call, so
// handing it an empty array hides the tabs without touching persisted state.
%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController

- (void)pinnedTimelinesRepository:(id)repository
    didChangeWithPinnedTimelineModels:(NSArray*)models {
    PinnedTimelinesRepository = repository;
    if (models.count > 0) {
        LastPinnedTimelineModels = [models copy];
    }
    BOOL hide = [BHTSettings boolForKey:@"hide_custom_timelines"];

    %orig(repository, hide ? @[] : models);
    SyncHomeAddTabButton(self, hide);
}

- (id)tfn_navigationBarAccessoryView {
    id accessoryView = %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
    return accessoryView;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
}

- (BOOL)tfn_supportsTabBarCollapsing {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? NO : %orig;
}

- (BOOL)tfn_prefersTabBarPinned {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? YES : %orig;
}

%end

// X 12.9 also registers an Objective-C-visible compatibility name for the Home
// container.  Keep the same safe, non-persisting behavior on that path.
%group BHTX129HomeContainer

%hook HomeTimelineContainerViewController

- (void)pinnedTimelinesRepository:(id)repository
    didChangeWithPinnedTimelineModels:(NSArray*)models {
    PinnedTimelinesRepository = repository;
    if (models.count > 0) LastPinnedTimelineModels = [models copy];
    BOOL hide = [BHTSettings boolForKey:@"hide_custom_timelines"];
    %orig(repository, hide ? @[] : models);
    SyncHomeAddTabButton(self, hide);
}

- (id)tfn_navigationBarAccessoryView {
    id accessory = %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
    return accessory;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
}

- (BOOL)tfn_supportsTabBarCollapsing {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? NO : %orig;
}

- (BOOL)tfn_prefersTabBarPinned {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? YES : %orig;
}

%end

%end

// While hiding, the overridden pinned-tabs feature switches make the app compute
// an empty pinned list; freeze writes so it can't overwrite the real tabs.
%hook _TtC32TwitterHomeFeatureImplementation31CachedPinnedTimelinesRepository

- (void)updatePinnedTimelines:(id)timelines {
    if (!PinnedTimelinesWriteBypass && [BHTSettings boolForKey:@"hide_custom_timelines"]) {
        return;
    }

    %orig;
}

%end

// MARK: - Force tweet images to full frame

%hook T1StandardStatusAttachmentViewAdapter

// attachmentType 2 = photos, displayType 1 = full frame
- (NSUInteger)displayType {
    if (self.attachmentType == 2) {
        return [BHTSettings boolForKey:@"force_tweet_full_frame"] ? 1 : %orig;
    }

    return %orig;
}

%end

// MARK: - Hide the Spaces bar

// The bar is still the repurposed Fleets line; both home timeline implementations
// share this visibility gate, re-evaluated on every content or settings update.
%hook T1FleetLineHeaderController

- (BOOL)_t1_shouldShowFleetLine {
    if ([BHTSettings boolForKey:@"hide_spaces"]) {
        return NO;
    }

    return %orig;
}

%end

// Target the update-indicator controller rather than every TFNPillControl in
// the app (other sheets and banners reuse that control class).
%hook TUIUpdateIndicator

- (void)viewDidLayoutSubviews {
    %orig;
    if ([BHTSettings boolForKey:@"hide_timeline_prompts"]) {
        self.pillControl.hidden = YES;
        self.pillControl.alpha = 0;
        self.pillControl.userInteractionEnabled = NO;
    }
}

%end

// MARK: - Hide "Discover more", who-to-follow and prompts

// Resolves the class by name so mangled Swift names work; NSStringFromClass
// would only ever produce the demangled dotted form.
static BOOL IsInHierarchyOfClass(UIViewController* viewController, NSString* className) {
    Class targetClass = NSClassFromString(className);
    if (!targetClass) {
        return NO;
    }

    UIViewController* currentVC = viewController;

    while (currentVC) {
        if ([currentVC isKindOfClass:targetClass]) {
            return YES;
        }

        if (currentVC.parentViewController) {
            currentVC = currentVC.parentViewController;
        } else if (currentVC.navigationController) {
            currentVC = currentVC.navigationController;
        } else if (currentVC.presentingViewController) {
            currentVC = currentVC.presentingViewController;
        } else {
            break;
        }
    }

    return NO;
}

static NSString* ItemEntryID(id viewModel) {
    if (![viewModel respondsToSelector:@selector(entryID)]) {
        return nil;
    }

    NSString* entryID = [viewModel performSelector:@selector(entryID)];
    return [entryID isKindOfClass:[NSString class]] ? entryID : nil;
}

static NSString* ItemScribeComponent(id viewModel) {
    if (![viewModel respondsToSelector:@selector(scribeComponent)]) {
        return nil;
    }

    NSString* component = [viewModel performSelector:@selector(scribeComponent)];
    return [component isKindOfClass:[NSString class]] ? component : nil;
}

static const char* SkipObjCTypeQualifiers(const char* type) {
    if (!type) return NULL;
    while (*type == 'r' || *type == 'n' || *type == 'N' ||
           *type == 'o' || *type == 'O' || *type == 'R' ||
           *type == 'V') {
        type++;
    }
    return type;
}

static BOOL MethodReturnsObject(id object, SEL selector) {
    if (!object || !selector ||
        ![object respondsToSelector:selector]) {
        return NO;
    }
    Method method =
        class_getInstanceMethod([object class], selector);
    if (!method) return NO;
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* unqualified =
        SkipObjCTypeQualifiers(returnType);
    return unqualified && unqualified[0] == '@';
}

static id ItemObjectValueAllowingUntypedIvar(
    id viewModel, SEL selector, const char* ivarName,
    BOOL allowUntypedIvar) {
    if (!viewModel) return nil;

    if (MethodReturnsObject(viewModel, selector)) {
        return ((id (*)(id, SEL))objc_msgSend)(viewModel, selector);
    }

    Ivar ivar = class_getInstanceVariable([viewModel class], ivarName);
    if (!ivar && ivarName[0] != '_') {
        NSString* name = [NSString stringWithUTF8String:ivarName];
        NSString* underscored = [@"_" stringByAppendingString:name];
        ivar = class_getInstanceVariable([viewModel class], underscored.UTF8String);
    }
    if (!ivar) return nil;

    const char* type =
        SkipObjCTypeQualifiers(ivar_getTypeEncoding(ivar));
    BOOL objectIvar = type && type[0] == '@';
    BOOL untypedIvar =
        !type || type[0] == '\0' || type[0] == '?';
    if (!objectIvar &&
        !(allowUntypedIvar && untypedIvar)) {
        return nil;
    }
    return object_getIvar(viewModel, ivar);
}

static id ItemObjectValue(id viewModel, SEL selector,
                          const char* ivarName) {
    return ItemObjectValueAllowingUntypedIvar(
        viewModel, selector, ivarName, NO);
}

static NSString* ItemStringValue(id object, SEL selector,
                                 const char* ivarName) {
    id value = ItemObjectValue(object, selector, ivarName);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSString* ItemReadableTextValue(id object, SEL selector,
                                       const char* ivarName) {
    id value = ItemObjectValue(object, selector, ivarName);
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSAttributedString.class]) {
        return [(NSAttributedString*)value string];
    }

    // X may expose display text through a small model rather than a raw
    // NSString. Follow only its public-facing string/text accessors and stop
    // after one level so timeline filtering remains bounded.
    for (NSString* nestedSelectorName in @[@"string", @"text",
                                            @"displayText"]) {
        SEL nestedSelector = NSSelectorFromString(nestedSelectorName);
        id nested =
            ItemObjectValue(value, nestedSelector,
                            nestedSelectorName.UTF8String);
        if ([nested isKindOfClass:NSString.class]) return nested;
        if ([nested isKindOfClass:NSAttributedString.class]) {
            return [(NSAttributedString*)nested string];
        }
    }
    return nil;
}

static Class BHTStatusItemViewModelClass(void) {
    static Class cls;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cls = NSClassFromString(
            @"T1URTTimelineStatusItemViewModel");
    });
    return cls;
}

static Class BHTTwitterStatusClass(void) {
    static Class cls;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cls = NSClassFromString(@"TFNTwitterStatus");
    });
    return cls;
}

static BOOL IsPrimaryForYouTimelineController(
    TFNItemsDataViewController* dataViewController) {
    if (!dataViewController) return NO;

    Class urtControllerClass = NSClassFromString(@"T1URTViewController");
    if (!urtControllerClass ||
        ![dataViewController isKindOfClass:urtControllerClass]) {
        return NO;
    }

    NSString* location =
        ItemStringValue(dataViewController, @selector(adDisplayLocation),
                        "adDisplayLocation");
    if (![location isEqualToString:@"TIMELINE_HOME"]) {
        return NO;
    }

    id urtTimeline =
        ItemObjectValue(dataViewController,
                        NSSelectorFromString(@"urtTimeline"), "urtTimeline");
    NSNumber* role = BHTHomeTimelineRoleForTimeline(urtTimeline);
    // Re-evaluate the current object on every section update. Never carry a
    // positive controller decision across an unknown or explicitly non-For You
    // timeline, since X is free to reuse controllers between feeds.
    return role.integerValue ==
           BHTHomeTimelineRolePrimaryForYou;
}

static id StatusFromTimelineItem(id item) {
    id viewModel = unwrapDataViewItem(item);
    Class statusItemClass = BHTStatusItemViewModelClass();
    Class statusClass = BHTTwitterStatusClass();
    if (!statusItemClass || !statusClass ||
        ![viewModel isKindOfClass:statusItemClass]) {
        return nil;
    }

    // Prefer X 12.9's compatibility accessor because its Objective-C return
    // signature can be verified before messaging it.
    id tweet =
        ItemObjectValue(viewModel, NSSelectorFromString(@"tweet"), "tweet");
    if ([tweet isKindOfClass:statusClass]) return tweet;

    // Some builds store the same object only in a Swift-backed `status` ivar
    // without a useful type encoding. Keep this narrow, final fallback after
    // the verified accessor and validate the resolved class immediately.
    id status = ItemObjectValueAllowingUntypedIvar(
        viewModel, NSSelectorFromString(@"status"), "status", YES);
    return [status isKindOfClass:statusClass] ? status : nil;
}

static id RepresentedStatus(id status) {
    if (!status) return nil;
    Class statusClass = BHTTwitterStatusClass();
    if (!statusClass) return nil;

    id represented =
        ItemObjectValue(status, NSSelectorFromString(@"representedStatus"),
                        "representedStatus");
    if ([represented isKindOfClass:statusClass]) {
        return represented;
    }

    id retweeted =
        ItemObjectValue(status, NSSelectorFromString(@"retweetedStatus"),
                        "retweetedStatus");
    return [retweeted isKindOfClass:statusClass] ? retweeted : status;
}

static void AddUsernameCandidates(NSMutableArray<NSString*>* candidates,
                                  id status) {
    if (!status) return;
    NSArray<NSString*>* values = @[
        ItemStringValue(status, NSSelectorFromString(@"fromUserName"),
                        "fromUserName") ?: @"",
        ItemStringValue(status, NSSelectorFromString(@"fromUserFullName"),
                        "fromUserFullName") ?: @"",
    ];
    for (NSString* value in values) {
        if (value.length > 0 && ![candidates containsObject:value]) {
            [candidates addObject:value];
        }
    }
}

static NSString* ReadableTextFromDisplayModel(id model) {
    if (!model) return nil;
    struct {
        const char* selector;
        const char* ivar;
    } candidates[] = {
        {"attributedString", "attributedString"},
        {"string", "string"},
        {"text", "text"},
        {"displayText", "displayText"},
    };
    for (NSUInteger index = 0;
         index < sizeof(candidates) / sizeof(candidates[0]); index++) {
        NSString* value = ItemReadableTextValue(
            model,
            NSSelectorFromString(
                [NSString stringWithUTF8String:
                              candidates[index].selector]),
            candidates[index].ivar);
        if (value.length > 0) return value;
    }
    return nil;
}

static NSString* VisiblePostText(id status) {
    if (!status) return nil;

    // Note Tweets can expose a shortened legacy `text`; prefer the dedicated
    // full-note model before consulting those compatibility accessors.
    id fullNoteModel = ItemObjectValue(
        status,
        NSSelectorFromString(
            @"_tfn_fullNoteTweetDisplayTextModel"),
        "_fullNoteTweetDisplayTextModel");
    NSString* modelText =
        ReadableTextFromDisplayModel(fullNoteModel);
    if (modelText.length > 0) return modelText;

    id displayTextModel =
        ItemObjectValue(status,
                        NSSelectorFromString(@"displayTextModel"),
                        "_displayTextModel");
    modelText = ReadableTextFromDisplayModel(displayTextModel);
    if (modelText.length > 0) return modelText;

    struct {
        const char* selector;
        const char* ivar;
    } candidates[] = {
        {"fullText", "fullText"},
        {"text", "text"},
        {"displayText", "displayText"},
        {"originalText", "originalText"},
    };

    for (NSUInteger index = 0;
         index < sizeof(candidates) / sizeof(candidates[0]); index++) {
        NSString* value =
            ItemReadableTextValue(
                status,
                NSSelectorFromString(
                    [NSString stringWithUTF8String:
                                  candidates[index].selector]),
                candidates[index].ivar);
        if (value.length > 0) return value;
    }
    return nil;
}

static BOOL ComputeShouldHideForYouKeywordItem(
    id item, BOOL hasUsernameFilters, BOOL hasPostTextFilters) {
    id outerStatus = StatusFromTimelineItem(item);
    if (!outerStatus) return NO;

    id representedStatus = RepresentedStatus(outerStatus);
    if (!representedStatus) return NO;

    if (hasUsernameFilters) {
        NSMutableArray<NSString*>* candidates =
            [NSMutableArray arrayWithCapacity:4];
        AddUsernameCandidates(candidates, representedStatus);
        if (outerStatus != representedStatus) {
            // Include the reposting account as well as the visible post author.
            AddUsernameCandidates(candidates, outerStatus);
        }
        BOOL matchesUsername = [BHTForYouKeywordFilter
            matchesAnyUsernameCandidate:candidates];
        if (matchesUsername) {
            return YES;
        }
    }

    if (hasPostTextFilters) {
        NSString* postText = VisiblePostText(representedStatus);
        if ([BHTForYouKeywordFilter matchesPostText:postText]) {
            return YES;
        }
    }

    return NO;
}

static BOOL ShouldHideForYouKeywordItem(
    id item, NSUInteger generation, BOOL hasUsernameFilters,
    BOOL hasPostTextFilters) {
    id cacheOwner = unwrapDataViewItem(item);
    Class statusItemClass = BHTStatusItemViewModelClass();
    if (!statusItemClass ||
        ![cacheOwner isKindOfClass:statusItemClass]) {
        return NO;
    }

    // URT item view models are immutable after delivery and can be considered
    // repeatedly while X rebuilds sections. Keep exactly one packed decision
    // per item; a filter edit increments the generation and invalidates it.
    // This function is called only after the strict For You controller gate,
    // so a cached decision is never consulted from Following.
    NSNumber* cached =
        objc_getAssociatedObject(cacheOwner,
                                 &kBHTForYouKeywordDecisionKey);
    if (cached) {
        NSUInteger packed = cached.unsignedIntegerValue;
        if ((packed >> 1) == generation) {
            return (packed & 1u) != 0;
        }
    }

    BOOL hidden = ComputeShouldHideForYouKeywordItem(
        cacheOwner, hasUsernameFilters, hasPostTextFilters);
    objc_setAssociatedObject(
        cacheOwner, &kBHTForYouKeywordDecisionKey,
        @((generation << 1) | (hidden ? 1u : 0u)),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return hidden;
}

static BOOL ItemHasTopicBanner(id viewModel) {
    id banner = ItemObjectValue(viewModel, NSSelectorFromString(@"banner"), "banner");
    NSString* bannerClass = banner ? NSStringFromClass([banner classForCoder]) : nil;
    return [bannerClass isEqualToString:@"TFNTwitterURTTimelineStatusTopicBanner"] ||
           [bannerClass hasSuffix:@".URTTimelineStatusTopicBanner"];
}

static BOOL StringContainsTopic(NSString* value) {
    return [value isKindOfClass:[NSString class]] &&
           [[value lowercaseString] containsString:@"topic"];
}

static BOOL StringIsTopicSuggestion(NSString* value) {
    if (!StringContainsTopic(value)) {
        return NO;
    }
    NSString* lower = [value lowercaseString];
    return [lower containsString:@"follow"] || [lower containsString:@"suggest"];
}

static BOOL ShouldHideTimelineItem(id item, BOOL hideWhoToFollow, BOOL hidePrompts,
                                   BOOL hideDiscoverMore, BOOL hideTopics,
                                   BOOL hideTopicsToFollow, BOOL inConversation,
                                   BOOL inProfile,
                                   BOOL filterForYouKeywords,
                                   NSUInteger keywordFilterGeneration,
                                   BOOL hasUsernameFilters,
                                   BOOL hasPostTextFilters) {
    id viewModel = unwrapDataViewItem(item);
    NSString* className = NSStringFromClass([viewModel classForCoder]);
    NSString* component = ItemScribeComponent(viewModel);
    NSString* entryID = ItemEntryID(viewModel);

    if (hidePrompts && [className isEqualToString:@"TwitterURT.URTTimelinePromptViewModel"]) {
        return YES;
    }

    if (hideWhoToFollow && [component isEqualToString:@"suggest_who_to_follow"]) {
        return YES;
    }

    if (hideTopics && ItemHasTopicBanner(viewModel)) {
        return YES;
    }

    BOOL isTopicCollection =
        [className isEqualToString:@"T1TwitterSwift.URTTimelineTopicCollectionViewModel"] ||
        [className isEqualToString:@"TwitterURT.URTTimelineTopicCollectionViewModel"] ||
        [className hasSuffix:@".URTTimelineTopicCollectionViewModel"];
    if (hideTopicsToFollow && inProfile &&
        (isTopicCollection || StringIsTopicSuggestion(component) ||
         StringIsTopicSuggestion(entryID))) {
        return YES;
    }

    if (hideTopics &&
        [className isEqualToString:@"TwitterURT.URTTimelinePromptViewModel"] &&
        (StringContainsTopic(component) || StringContainsTopic(entryID))) {
        return YES;
    }

    if (hideDiscoverMore && inConversation &&
        [entryID hasPrefix:@"tweetdetailrelatedtweets"]) {
        return YES;
    }

    if (hideWhoToFollow && [entryID containsString:@"who-to-follow"]) {
        return YES;
    }

    if (filterForYouKeywords &&
        ShouldHideForYouKeywordItem(
            viewModel, keywordFilterGeneration, hasUsernameFilters,
            hasPostTextFilters)) {
        return YES;
    }

    return NO;
}

static NSArray* FilteredTimelineSections(TFNItemsDataViewController* dataViewController,
                                         NSArray* sections) {
    BOOL hideWhoToFollow = [BHTSettings boolForKey:@"hide_who_to_follow"];
    BOOL hidePrompts = [BHTSettings boolForKey:@"hide_timeline_prompts"];
    BOOL hideDiscoverMore = [BHTSettings boolForKey:@"hide_discover_more"];
    BOOL hideTopics = [BHTSettings boolForKey:@"hide_topics"];
    BOOL hideTopicsToFollow = [BHTSettings boolForKey:@"hide_topics_to_follow"];
    BOOL inConversation =
        IsInHierarchyOfClass(dataViewController, @"T1ConversationContainerViewController");
    BOOL inProfile = IsInHierarchyOfClass(dataViewController, @"T1ProfileViewController");
    BOOL hasUsernameFilters = NO;
    BOOL hasPostTextFilters = NO;
    NSUInteger keywordFilterGeneration =
        [BHTForYouKeywordFilter
            filterGenerationWithUsernameFilters:&hasUsernameFilters
                                 postTextFilters:&hasPostTextFilters];
    BOOL filterForYouKeywords =
        (hasUsernameFilters || hasPostTextFilters) &&
        IsPrimaryForYouTimelineController(dataViewController);

    if (!hideWhoToFollow && !hidePrompts && !hideTopics &&
        !hideTopicsToFollow && !(hideDiscoverMore && inConversation) &&
        !filterForYouKeywords) {
        return sections;
    }

    // Modules can share a section with unrelated items, so filtering is per item;
    // a purely filtered section (like the Discover More one) empties and is dropped.
    BOOL modified = NO;
    NSMutableArray* filteredSections = [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < items.count; i++) {
            if (ShouldHideTimelineItem(items[i], hideWhoToFollow, hidePrompts,
                                       hideDiscoverMore, hideTopics,
                                       hideTopicsToFollow, inConversation,
                                       inProfile, filterForYouKeywords,
                                       keywordFilterGeneration,
                                       hasUsernameFilters,
                                       hasPostTextFilters)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        MarkEmptiedModuleChrome(items, removed);

        modified = YES;
        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    return modified ? [filteredSections copy] : sections;
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    %orig(FilteredTimelineSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(FilteredTimelineSections(self, sections), identifiers, animation, completion);
}

%end

%ctor {
    %init;

    Class timelineFactoryClass = NSClassFromString(@"T1TimelineFactory");
    Class homeTimelineClass = NSClassFromString(@"TFNTwitterHomeTimeline");
    NSArray<NSString*>* requiredFactorySelectors = @[
        @"homeTimelineForAccount:",
        @"homeCountryFilteredTimelineForAccount:",
        @"homeTopicFilteredTimelineForAccount:",
        @"homeLatestTimelineForAccount:",
        @"homeRankedFollowingTimelineForAccount:",
        @"rootViewControllerForHomeTimeline:homeCountryFilteredTimeline:homeLatestTimeline:homeRankedFollowingTimeline:account:",
    ];
    BOOL canTrackForYouProvenance =
        timelineFactoryClass && homeTimelineClass &&
        [homeTimelineClass
            instancesRespondToSelector:@selector(deserializeStream)];
    for (NSString* selectorName in requiredFactorySelectors) {
        if (![timelineFactoryClass
                instancesRespondToSelector:NSSelectorFromString(
                                               selectorName)]) {
            canTrackForYouProvenance = NO;
            break;
        }
    }
    if (canTrackForYouProvenance) {
        %init(BHTForYouTimelineProvenance);
    }

    Class compatibilityClass = NSClassFromString(@"HomeTimelineContainerViewController");
    Class swiftClass = NSClassFromString(
        @"TwitterHomeFeatureImplementation.HomeTimelineContainerViewController");
    if (compatibilityClass && compatibilityClass != swiftClass) {
        %init(BHTX129HomeContainer);
    }
}
