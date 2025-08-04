#!/bin/bash

# Comment out unused functions in context_builder_agent.ex
FILE="lib/rubber_duck/agents/context_builder_agent.ex"

# List of unused functions
UNUSED_FUNCTIONS=(
  "build_context_request"
  "build_new_context"
  "gather_source_contexts"
  "fetch_from_source"
  "fetch_memory_context"
  "fetch_code_context"
  "fetch_doc_context"
  "fetch_conversation_context"
  "fetch_planning_context"
  "fetch_custom_context"
  "prioritize_context_entries"
  "calculate_entry_score"
  "calculate_recency_score"
  "calculate_importance_score"
  "matches_preferences?"
  "optimize_context"
  "deduplicate_entries"
  "similar_entry_exists?"
  "similarity_score"
  "apply_compression"
  "apply_summarization"
  "truncate_to_limit"
  "get_cached_context"
  "cache_context"
  "context_still_valid?"
  "evict_oldest_cache_entry"
  "invalidate_cache_entries"
  "invalidate_source_cache"
  "start_streaming_build"
  "determine_sources"
  "build_code_entries"
  "apply_context_updates"
  "build_context_metadata"
  "calculate_total_tokens"
  "find_oldest_timestamp"
  "find_newest_timestamp"
  "content_to_string"
  "update_build_metrics"
  "calculate_cache_hit_rate"
  "generate_request_id"
  "generate_source_id"
)

# Create a temporary file
TMP_FILE="${FILE}.tmp"
cp "$FILE" "$TMP_FILE"

# For each unused function, comment it out
for func in "${UNUSED_FUNCTIONS[@]}"; do
  # Use sed to comment out the function definition and its body
  # This handles multi-line function bodies
  sed -i "/defp ${func}/,/^  end$/s/^/  # /" "$TMP_FILE" 2>/dev/null || true
done

# Move the temporary file back
mv "$TMP_FILE" "$FILE"

echo "Commented out unused functions in $FILE"