static void testTimelineCleanupClassification(void) {
    BHTTimelineCleanupKind whoToFollow =
        BHTTimelineCleanupKindWhoToFollow;
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   nil, @"suggest_who_to_follow", nil) &
               whoToFollow) != 0,
              @"Legacy Who to follow component is recognized");
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   nil, @"who_to_follow", nil) &
               whoToFollow) != 0,
              @"Current Who to follow component is recognized");
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   nil, @"user_recommendations_urt", nil) &
               whoToFollow) != 0,
              @"User recommendation module aliases are recognized");
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   nil, @"suggest_who_to_subscribe_module", nil) &
               whoToFollow) != 0,
              @"Account subscription recommendations are recognized");
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   nil, @"list_creation_recommended_users_timeline", nil) &
               whoToFollow) == 0,
              @"List editor recommendations stay available");

    BHTTimelineCleanupKind discoverMore =
        BHTTimelineCleanupKindDiscoverMore;
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   nil, @"discover_more", nil) &
               discoverMore) != 0,
              @"Discover more component is recognized");
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   nil, nil, @"tweetdetailrelatedtweets-123") &
               discoverMore) != 0,
              @"Conversation related-post entry is recognized");

    BHTTimelineCleanupKind topicSuggestion =
        BHTTimelineCleanupKindTopicSuggestion;
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   nil, @"suggest_topics_module", nil) &
               topicSuggestion) != 0,
              @"Topic suggestion module is recognized");
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   nil, @"utt_topic_carousel", nil) &
               topicSuggestion) != 0,
              @"Topic carousel is recognized");
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   @"TwitterURT.URTTimelineTopicCollectionViewModel",
                   nil, nil) &
               topicSuggestion) != 0,
              @"Topic collection class is recognized");

    BHTTimelineCleanupKind prompt = BHTTimelineCleanupKindPrompt;
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   nil, @"relevance_prompt_module", nil) &
               prompt) != 0,
              @"Relevance prompt is recognized");
    NSCAssert((BHTTimelineCleanupKindsForIdentifiers(
                   @"TwitterURT.URTTimelinePromptViewModel", nil,
                   nil) &
               prompt) != 0,
              @"Prompt view model is recognized");

    NSCAssert(BHTTimelineCleanupKindsForIdentifiers(
                  nil, @"suggested_tweet", @"home-conversation-42") ==
                  BHTTimelineCleanupKindNone,
              @"Ordinary suggested posts remain visible");
    NSCAssert(BHTTimelineCleanupKindsForIdentifiers(
                  nil, @"topics_timeline", nil) ==
                  BHTTimelineCleanupKindNone,
              @"A user-opened Topic timeline remains available");
}
