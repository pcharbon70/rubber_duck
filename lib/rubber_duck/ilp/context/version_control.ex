defmodule RubberDuck.ILP.Context.VersionControl do
  @moduledoc """
  Version control for context evolution with Git-like branching.
  Supports branching, merging, and conflict resolution for context data.
  """

  defstruct [
    :branches,
    :commits,
    :merge_strategies,
    :current_branch,
    :conflict_resolver
  ]

  @doc """
  Initializes the version control system.
  """
  def initialize(opts \\ []) do
    %__MODULE__{
      branches: %{"main" => %{head: nil, created_at: System.monotonic_time(:millisecond)}},
      commits: %{},
      merge_strategies: [:auto, :manual, :semantic_merge, :content_aware],
      current_branch: "main",
      conflict_resolver: Keyword.get(opts, :conflict_resolver, :auto)
    }
  end

  @doc """
  Creates a new branch from a base context.
  """
  def create_branch(vc, base_context_id, branch_name) do
    case Map.has_key?(vc.branches, branch_name) do
      true ->
        {:error, :branch_already_exists}
      
      false ->
        # Create commit for base context if not exists
        {updated_vc, commit_id} = ensure_commit_exists(vc, base_context_id)
        
        new_branch = %{
          head: commit_id,
          created_at: System.monotonic_time(:millisecond),
          parent: vc.current_branch,
          base_commit: commit_id
        }
        
        updated_branches = Map.put(updated_vc.branches, branch_name, new_branch)
        final_vc = %{updated_vc | branches: updated_branches}
        
        branch_id = generate_branch_id(branch_name, commit_id)
        {:ok, branch_id}
    end
  end

  @doc """
  Commits context changes to the current branch.
  """
  def commit_context(vc, context_id, content, message, metadata \\ %{}) do
    commit_id = generate_commit_id()
    parent_commit = get_branch_head(vc, vc.current_branch)
    
    commit = %{
      id: commit_id,
      context_id: context_id,
      content_hash: calculate_content_hash(content),
      message: message,
      metadata: metadata,
      parent: parent_commit,
      author: "system",
      timestamp: System.monotonic_time(:millisecond),
      branch: vc.current_branch
    }
    
    # Update commits and branch head
    updated_commits = Map.put(vc.commits, commit_id, commit)
    updated_branches = put_in(vc.branches[vc.current_branch].head, commit_id)
    
    updated_vc = %{vc | commits: updated_commits, branches: updated_branches}
    {:ok, commit_id, updated_vc}
  end

  @doc """
  Merges two branches with conflict resolution.
  """
  def merge_branches(vc, source_branch, target_branch, strategy \\ :auto) do
    case {Map.get(vc.branches, source_branch), Map.get(vc.branches, target_branch)} do
      {nil, _} ->
        {:error, :source_branch_not_found}
      
      {_, nil} ->
        {:error, :target_branch_not_found}
      
      {source, target} ->
        case perform_merge(vc, source, target, source_branch, target_branch, strategy) do
          {:ok, merged_commit_id, updated_vc} ->
            {:ok, merged_commit_id}
          
          {:conflict, conflicts, resolution_data} ->
            case strategy do
              :auto ->
                auto_resolve_conflicts(vc, conflicts, resolution_data, target_branch)
              
              :manual ->
                {:conflict, conflicts, resolution_data}
              
              _ ->
                smart_resolve_conflicts(vc, conflicts, resolution_data, target_branch, strategy)
            end
          
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Gets the commit history for a branch.
  """
  def get_commit_history(vc, branch_name, limit \\ 10) do
    case Map.get(vc.branches, branch_name) do
      nil ->
        {:error, :branch_not_found}
      
      branch ->
        history = build_commit_history(vc, branch.head, limit)
        {:ok, history}
    end
  end

  @doc """
  Gets the diff between two commits.
  """
  def get_commit_diff(vc, commit_id1, commit_id2) do
    case {Map.get(vc.commits, commit_id1), Map.get(vc.commits, commit_id2)} do
      {nil, _} ->
        {:error, :commit1_not_found}
      
      {_, nil} ->
        {:error, :commit2_not_found}
      
      {commit1, commit2} ->
        diff = calculate_commit_diff(commit1, commit2)
        {:ok, diff}
    end
  end

  @doc """
  Checks out a specific branch.
  """
  def checkout_branch(vc, branch_name) do
    case Map.has_key?(vc.branches, branch_name) do
      true ->
        updated_vc = %{vc | current_branch: branch_name}
        {:ok, updated_vc}
      
      false ->
        {:error, :branch_not_found}
    end
  end

  @doc """
  Lists all branches with their status.
  """
  def list_branches(vc) do
    branches = Enum.map(vc.branches, fn {name, branch} ->
      %{
        name: name,
        head: branch.head,
        created_at: branch.created_at,
        is_current: name == vc.current_branch,
        commit_count: count_commits_in_branch(vc, name)
      }
    end)
    
    {:ok, branches}
  end

  @doc """
  Deletes a branch (cannot delete current branch or main).
  """
  def delete_branch(vc, branch_name) do
    cond do
      branch_name == "main" ->
        {:error, :cannot_delete_main_branch}
      
      branch_name == vc.current_branch ->
        {:error, :cannot_delete_current_branch}
      
      not Map.has_key?(vc.branches, branch_name) ->
        {:error, :branch_not_found}
      
      true ->
        updated_branches = Map.delete(vc.branches, branch_name)
        updated_vc = %{vc | branches: updated_branches}
        {:ok, updated_vc}
    end
  end

  # Private functions

  defp ensure_commit_exists(vc, context_id) do
    # Check if there's already a commit for this context
    existing_commit = Enum.find(vc.commits, fn {_id, commit} ->
      commit.context_id == context_id
    end)
    
    case existing_commit do
      {commit_id, _commit} ->
        {vc, commit_id}
      
      nil ->
        # Create a new commit
        commit_id = generate_commit_id()
        commit = %{
          id: commit_id,
          context_id: context_id,
          content_hash: calculate_content_hash(context_id),
          message: "Initial commit for context #{context_id}",
          metadata: %{},
          parent: nil,
          author: "system",
          timestamp: System.monotonic_time(:millisecond),
          branch: vc.current_branch
        }
        
        updated_commits = Map.put(vc.commits, commit_id, commit)
        updated_vc = %{vc | commits: updated_commits}
        {updated_vc, commit_id}
    end
  end

  defp get_branch_head(vc, branch_name) do
    case Map.get(vc.branches, branch_name) do
      nil -> nil
      branch -> branch.head
    end
  end

  defp perform_merge(vc, source_branch, target_branch, source_name, target_name, strategy) do
    source_commits = get_branch_commits(vc, source_name)
    target_commits = get_branch_commits(vc, target_name)
    
    # Find common ancestor
    common_ancestor = find_common_ancestor(source_commits, target_commits)
    
    # Get changes since common ancestor
    source_changes = get_changes_since(vc, source_commits, common_ancestor)
    target_changes = get_changes_since(vc, target_commits, common_ancestor)
    
    # Detect conflicts
    conflicts = detect_conflicts(source_changes, target_changes)
    
    case conflicts do
      [] ->
        # No conflicts - can merge automatically
        merged_commit_id = create_merge_commit(vc, source_branch, target_branch, source_name, target_name)
        
        # Update target branch head
        updated_branches = put_in(vc.branches[target_name].head, merged_commit_id)
        updated_vc = %{vc | branches: updated_branches}
        
        {:ok, merged_commit_id, updated_vc}
      
      _ ->
        # Conflicts detected
        resolution_data = %{
          source_branch: source_name,
          target_branch: target_name,
          common_ancestor: common_ancestor,
          source_changes: source_changes,
          target_changes: target_changes
        }
        
        {:conflict, conflicts, resolution_data}
    end
  end

  defp auto_resolve_conflicts(vc, conflicts, resolution_data, target_branch) do
    # Simple auto-resolution: take target branch changes for conflicts
    resolved_changes = Enum.map(conflicts, fn conflict ->
      case conflict.type do
        :content_conflict ->
          %{conflict | resolution: :take_target}
        
        :metadata_conflict ->
          %{conflict | resolution: :merge_metadata}
        
        _ ->
          %{conflict | resolution: :take_target}
      end
    end)
    
    # Create merge commit with resolved conflicts
    merge_commit_id = create_resolved_merge_commit(vc, resolved_changes, resolution_data, target_branch)
    {:ok, merge_commit_id}
  end

  defp smart_resolve_conflicts(vc, conflicts, resolution_data, target_branch, strategy) do
    case strategy do
      :semantic_merge ->
        semantic_resolve_conflicts(vc, conflicts, resolution_data, target_branch)
      
      :content_aware ->
        content_aware_resolve_conflicts(vc, conflicts, resolution_data, target_branch)
      
      _ ->
        auto_resolve_conflicts(vc, conflicts, resolution_data, target_branch)
    end
  end

  defp semantic_resolve_conflicts(vc, conflicts, resolution_data, target_branch) do
    # Resolve conflicts based on semantic understanding
    resolved_changes = Enum.map(conflicts, fn conflict ->
      resolution = case analyze_semantic_conflict(conflict) do
        :prefer_source -> :take_source
        :prefer_target -> :take_target
        :merge_both -> :merge_semantic
        _ -> :take_target
      end
      
      %{conflict | resolution: resolution}
    end)
    
    merge_commit_id = create_resolved_merge_commit(vc, resolved_changes, resolution_data, target_branch)
    {:ok, merge_commit_id}
  end

  defp content_aware_resolve_conflicts(vc, conflicts, resolution_data, target_branch) do
    # Resolve conflicts based on content analysis
    resolved_changes = Enum.map(conflicts, fn conflict ->
      resolution = case analyze_content_conflict(conflict) do
        :source_more_recent -> :take_source
        :target_more_complete -> :take_target
        :merge_beneficial -> :merge_content
        _ -> :take_target
      end
      
      %{conflict | resolution: resolution}
    end)
    
    merge_commit_id = create_resolved_merge_commit(vc, resolved_changes, resolution_data, target_branch)
    {:ok, merge_commit_id}
  end

  defp build_commit_history(vc, commit_id, limit, acc \\ [])
  defp build_commit_history(_vc, nil, _limit, acc), do: Enum.reverse(acc)
  defp build_commit_history(_vc, _commit_id, 0, acc), do: Enum.reverse(acc)
  defp build_commit_history(vc, commit_id, limit, acc) do
    case Map.get(vc.commits, commit_id) do
      nil ->
        Enum.reverse(acc)
      
      commit ->
        new_acc = [commit | acc]
        build_commit_history(vc, commit.parent, limit - 1, new_acc)
    end
  end

  defp calculate_commit_diff(commit1, commit2) do
    %{
      commit1_id: commit1.id,
      commit2_id: commit2.id,
      content_hash_diff: commit1.content_hash != commit2.content_hash,
      metadata_diff: calculate_metadata_diff(commit1.metadata, commit2.metadata),
      timestamp_diff: commit2.timestamp - commit1.timestamp
    }
  end

  defp calculate_metadata_diff(metadata1, metadata2) do
    keys1 = Map.keys(metadata1) |> MapSet.new()
    keys2 = Map.keys(metadata2) |> MapSet.new()
    
    %{
      added_keys: MapSet.difference(keys2, keys1) |> MapSet.to_list(),
      removed_keys: MapSet.difference(keys1, keys2) |> MapSet.to_list(),
      changed_values: Map.keys(metadata1)
      |> Enum.filter(fn key ->
        Map.has_key?(metadata2, key) && Map.get(metadata1, key) != Map.get(metadata2, key)
      end)
    }
  end

  defp count_commits_in_branch(vc, branch_name) do
    case Map.get(vc.branches, branch_name) do
      nil -> 0
      branch -> count_commits_from_head(vc, branch.head)
    end
  end

  defp count_commits_from_head(vc, commit_id, count \\ 0)
  defp count_commits_from_head(_vc, nil, count), do: count
  defp count_commits_from_head(vc, commit_id, count) do
    case Map.get(vc.commits, commit_id) do
      nil -> count
      commit -> count_commits_from_head(vc, commit.parent, count + 1)
    end
  end

  defp get_branch_commits(vc, branch_name) do
    case Map.get(vc.branches, branch_name) do
      nil -> []
      branch -> collect_commits_from_head(vc, branch.head)
    end
  end

  defp collect_commits_from_head(vc, commit_id, acc \\ [])
  defp collect_commits_from_head(_vc, nil, acc), do: Enum.reverse(acc)
  defp collect_commits_from_head(vc, commit_id, acc) do
    case Map.get(vc.commits, commit_id) do
      nil -> Enum.reverse(acc)
      commit -> collect_commits_from_head(vc, commit.parent, [commit | acc])
    end
  end

  defp find_common_ancestor(source_commits, target_commits) do
    source_ids = Enum.map(source_commits, & &1.id) |> MapSet.new()
    
    Enum.find(target_commits, fn commit ->
      MapSet.member?(source_ids, commit.id)
    end)
  end

  defp get_changes_since(vc, commits, common_ancestor) do
    case common_ancestor do
      nil -> commits
      ancestor -> 
        Enum.take_while(commits, fn commit ->
          commit.id != ancestor.id
        end)
    end
  end

  defp detect_conflicts(source_changes, target_changes) do
    # Simplified conflict detection
    conflicts = []
    
    # Check for context ID conflicts
    source_contexts = Enum.map(source_changes, & &1.context_id) |> MapSet.new()
    target_contexts = Enum.map(target_changes, & &1.context_id) |> MapSet.new()
    
    conflicting_contexts = MapSet.intersection(source_contexts, target_contexts)
    
    context_conflicts = Enum.map(conflicting_contexts, fn context_id ->
      source_commit = Enum.find(source_changes, &(&1.context_id == context_id))
      target_commit = Enum.find(target_changes, &(&1.context_id == context_id))
      
      %{
        type: :content_conflict,
        context_id: context_id,
        source_commit: source_commit,
        target_commit: target_commit
      }
    end)
    
    conflicts ++ context_conflicts
  end

  defp create_merge_commit(vc, source_branch, target_branch, source_name, target_name) do
    commit_id = generate_commit_id()
    
    commit = %{
      id: commit_id,
      context_id: "merge_#{source_name}_into_#{target_name}",
      content_hash: calculate_content_hash("merge_commit"),
      message: "Merge branch '#{source_name}' into '#{target_name}'",
      metadata: %{
        merge_commit: true,
        source_branch: source_name,
        target_branch: target_name
      },
      parent: target_branch.head,
      merge_parent: source_branch.head,
      author: "system",
      timestamp: System.monotonic_time(:millisecond),
      branch: target_name
    }
    
    # Add commit to commits map (this would need to be done by caller)
    commit_id
  end

  defp create_resolved_merge_commit(vc, resolved_changes, resolution_data, target_branch) do
    commit_id = generate_commit_id()
    
    commit = %{
      id: commit_id,
      context_id: "resolved_merge_#{target_branch}",
      content_hash: calculate_content_hash("resolved_merge"),
      message: "Merge with conflict resolution",
      metadata: %{
        merge_commit: true,
        conflicts_resolved: length(resolved_changes),
        resolution_data: resolution_data
      },
      parent: get_branch_head(vc, target_branch),
      author: "system",
      timestamp: System.monotonic_time(:millisecond),
      branch: target_branch
    }
    
    commit_id
  end

  # Utility functions

  defp generate_commit_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp generate_branch_id(branch_name, base_commit) do
    "#{branch_name}_#{String.slice(base_commit || "none", 0, 8)}"
  end

  defp calculate_content_hash(content) when is_binary(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp calculate_content_hash(content) do
    :crypto.hash(:sha256, inspect(content)) |> Base.encode16(case: :lower)
  end

  defp analyze_semantic_conflict(_conflict) do
    # Simplified semantic analysis
    :prefer_target
  end

  defp analyze_content_conflict(_conflict) do
    # Simplified content analysis
    :target_more_complete
  end
end