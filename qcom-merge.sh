#!/bin/bash
set -euo pipefail

### CONSTANTS ###
# (This file must be edited directly to change these.)
# We add .git to the end later to avoid a warning.
declare -A _remote_urls=(
  [clo/audio-kernel]=https://git.codelinaro.org/clo/la/platform/vendor/opensource/audio-kernel
  [clo/camera-kernel]=https://git.codelinaro.org/clo/la/platform/vendor/opensource/camera-kernel
  [clo/data-kernel]=https://git.codelinaro.org/clo/la/platform/vendor/qcom-opensource/data-kernel
  [clo/dataipa]=https://git.codelinaro.org/clo/la/platform/vendor/opensource/dataipa
  [clo/datarmnet]=https://git.codelinaro.org/clo/la/platform/vendor/qcom/opensource/datarmnet
  [clo/datarmnet-ext]=https://git.codelinaro.org/clo/la/platform/vendor/qcom/opensource/datarmnet-ext
  [clo/display-drivers]=https://git.codelinaro.org/clo/la/platform/vendor/opensource/display-drivers
  [clo/fw-api]=https://git.codelinaro.org/clo/la/platform/vendor/qcom-opensource/wlan/fw-api
  [clo/msm]=https://git.codelinaro.org/clo/la/kernel/msm
  [clo/msm-3.10]=https://git.codelinaro.org/clo/la/kernel/msm-3.10
  [clo/msm-3.18]=https://git.codelinaro.org/clo/la/kernel/msm-3.18
  [clo/msm-4.4]=https://git.codelinaro.org/clo/la/kernel/msm-4.4
  [clo/msm-4.9]=https://git.codelinaro.org/clo/la/kernel/msm-4.9
  [clo/msm-4.14]=https://git.codelinaro.org/clo/la/kernel/msm-4.14
  [clo/msm-4.19]=https://git.codelinaro.org/clo/la/kernel/msm-4.19
  [clo/msm-5.4]=https://git.codelinaro.org/clo/la/kernel/msm-5.4
  [clo/msm-5.10]=https://git.codelinaro.org/clo/la/kernel/msm-5.10
  [clo/msm-5.15]=https://git.codelinaro.org/clo/la/kernel/msm-5.15
  [clo/prima]=https://git.codelinaro.org/clo/la/platform/vendor/qcom-opensource/wlan/prima
  [clo/qca-wifi-host-cmn]=https://git.codelinaro.org/clo/la/platform/vendor/qcom-opensource/wlan/qca-wifi-host-cmn
  [clo/qcacld-2.0]=https://git.codelinaro.org/clo/la/platform/vendor/qcom-opensource/wlan/qcacld-2.0
  [clo/qcacld-3.0]=https://git.codelinaro.org/clo/la/platform/vendor/qcom-opensource/wlan/qcacld-3.0
  [clo/video-driver]=https://git.codelinaro.org/clo/la/platform/vendor/opensource/video-driver
)
declare -a _sorted_remotes
_lastIFS="$IFS"; IFS=$'\n' _sorted_remotes=($(printf "%s\n" "${!_remote_urls[@]}" | sort -V)); IFS="$_lastIFS"; unset _lastIFS

declare -A _subtrees=(
  [clo/msm]=""
  [clo/msm-3.10]=""
  [clo/msm-3.18]=""
  [clo/msm-4.4]=""
  [clo/msm-4.9]=""
  [clo/msm-4.14]=""
  [clo/msm-4.19]=""
  [clo/msm-5.4]=""
  [clo/msm-5.10]=""
  [clo/msm-5.15]=""
  [clo/fw-api]=drivers/staging/fw-api
  [clo/qca-wifi-host-cmn]=drivers/staging/qca-wifi-host-cmn
  [clo/qcacld-3.0]=drivers/staging/qcacld-3.0
  [clo/audio-kernel]=techpack/audio
  [clo/camera-kernel]=techpack/camera
  [clo/dataipa]=techpack/dataipa
  [clo/datarmnet]=techpack/datarmnet
  [clo/datarmnet-ext]=techpack/datarmnet-ext
  [clo/display-drivers]=techpack/display
  [clo/video-driver]=techpack/video
)

# Map of chipset to required remotes, whitespace-separated and in merge order.
declare -A _chipset_remotes=(
  [sm8350]="clo/msm-5.4 clo/fw-api clo/qca-wifi-host-cmn clo/qcacld-3.0 clo/audio-kernel clo/camera-kernel clo/dataipa clo/datarmnet clo/datarmnet-ext clo/display-drivers clo/video-driver"
)
declare -a _sorted_chipsets
_lastIFS="$IFS"; IFS=$'\n' _sorted_chipsets=($(printf "%s\n" "${!_chipset_remotes[@]}" | sort -n)); IFS="$_lastIFS"; unset _lastIFS

_push_remote_template="lineage/%s-gerrit"



### UTILITY FUNCTIONS ###
is_true() {
  local var_name="$1"
  local default_value="${2:-n}"
  local value="${!var_name:-}"
  local effective_value="${value:-$default_value}"
  case "${effective_value,,}" in
    y|yes|true|on|1)
      return 0
      ;;
    n|no|false|off|0)
      return 1
      ;;
  esac
  echo "Expected boolean value (y/n) for $var_name; got '$value'" >&2
  exit 1
}

info() {
  printf "INFO: %s\n" "$*"
}



### VARIABLES ###
# CHIPSET
# - must be provided
# TAG
# - must be provided
# FORCE_FETCH (defaults to off; when off, saves time when already fetched)
_var_force_fetch=$(is_true FORCE_FETCH n && echo 1 || echo 0)
# NO_EDIT (defaults to on; saves time by not asking to edit commits without conflicts)
_var_no_edit=$(is_true NO_EDIT y && echo 1 || echo 0)
# MERGE_LOOKBACK (defaults to "3 months"; saves time when re-running this script by not re-
#                 attempting merges that are already present in the git log within this timeframe)
_var_merge_lookback="${MERGE_LOOKBACK:-3 months}"
# MERGE_EMPTY (defaults to off; when on, leaves a trail that a merge was attempted even if the repo
#              was already up to dates. saves time when re-running this script by not re-attempting
#              such merges, but RESUME_FROM_LAST_MERGE offers an alternative way to save some time)
_var_merge_empty=$(is_true MERGE_EMPTY n && echo 1 || echo 0)
# RESUME_FROM_LAST_MERGE (defaults to on; when on, saves time by continuing to merge repos from the
#                         last repo merged in the list of required repos for CHIPSET)
_var_resume_from_last_merge=$(is_true RESUME_FROM_LAST_MERGE y && echo 1 || echo 0)
# MERGE_GIT_ARGUMENTS (defaults to "--log=1500")
_var_merge_git_arguments="${MERGE_GIT_ARGUMENTS:-"--log=1500"}"
# PUSH_MERGE_REVIEW (defaults to off; performs a git push-merge-review after every merge)
_var_push_merge_review=$(is_true PUSH_MERGE_REVIEW n && echo 1 || echo 0)
# PUSH_REMOTE (defaults to lineage/$CHIPSET-gerrit; only used when PUSH_MERGE_REVIEW is on)
# - see main() for _var_push_remote assignment
# PUSH_REMOTE_BRANCH
# - must be provided when PUSH_MERGE_REVIEW is on
# INTO_NAME (defaults to the current branch name)
# - see merge_tags



### MAIN ###
main() {
  if [ -z "${CHIPSET:-}" ] || [ -z "${_chipset_remotes[$CHIPSET]:-}" ]; then
    echo "Please set CHIPSET to one of the following supported chipsets:" >&2
    printf "  %s\n" "$_sorted_chipsets"
    exit 1
  fi
  if [ -z "${TAG:-}" ]; then
    echo "Please set TAG to an upstream tag to be merged, e.g. LA.UM.9.14.r1-25800-LAHAINA.QSSI15.0" >&2
    exit 1
  fi
  if [ $_var_push_merge_review -eq 1 ]; then
    if ! which git-push-merge-review >/dev/null 2>/dev/null; then
      echo "PUSH_MERGE_REVIEW is on but git-push-merge-review script could not be found! Ensure it is in your PATH." >&2
      echo "You can find it at: https://github.com/LineageOS/scripts/blob/main/git-push-merge-review/git-push-merge-review" >&2
      echo "Or, if you would rather upload manually, set PUSH_MERGE_REVIEW=n." >&2
      exit 1
    fi
    if [ -z "${PUSH_REMOTE_BRANCH:-}" ]; then
      echo "Please set PUSH_REMOTE_BRANCH to the remote branch you'll be pushing to, e.g. 'lineage-20'." >&2
      exit 1
    fi
    if [ -z "${PUSH_REMOTE:-}" ]; then
      _var_push_remote="$(printf "$_push_remote_template\n" "$CHIPSET")"
    else
      _var_push_remote="$PUSH_REMOTE"
    fi
    if ! git remote get-url "$_var_push_remote" >/dev/null 2>&1; then
      echo "PUSH_REVIEW_MERGE is on but could not find remote '$_var_push_remote' to push to." >&2
      echo "Please set PUSH_REMOTE to an existing remote or add the missing remote." >&2
      exit 1
    fi
  fi
  initialize_remotes || return $?
  fetch_tags || return $?
  merge_tags || return $?
}



### PRIMARY FUNCTIONS ###
initialize_remotes() {
  local remote
  for remote in "${_sorted_remotes[@]}"; do
    local new_url="${_remote_urls[$remote]}.git"
    local current_url
    if ! current_url="$(git remote get-url "$remote" 2>/dev/null)"; then
      git remote add "$remote" "$new_url"
      continue
    fi
    if [ "$current_url" != "$new_url" ]; then
      echo "URL changed for $remote. Updating from $current_url to $new_url." >&2
      git remote set-url "$remote" "$new_url"
      sleep 1
    fi
  done
}

fetch_tags() {
  local any_fetch_tried=
  local remote
  for remote in ${_chipset_remotes[$CHIPSET]}; do
    local src="refs/tags/$TAG"
    local dst="refs/tags/$remote/$TAG"
    if [ $_var_force_fetch -eq 0 ]; then
      if git show-ref --quiet --tags "$dst"; then
        continue
      else
        any_fetch_tried=1
      fi
    fi
    echo "Fetching $TAG for $remote..."
    git fetch "$remote" "$src:$dst" || {
      local err=$?
      echo "Failed to fetch for $remote with error $err." >&2
      return $err
    }
  done
  if [ -z "$any_fetch_tried" ]; then
    info "All tags already fetched. Use FORCE_FETCH to fetch anyway."
  fi
}

merge_tags() {
  local -a edit_arg=()
  if [ $_var_no_edit -eq 1 ]; then
    edit_arg=(--no-edit)
  else
    edit_arg=(--edit)
  fi
  local current_branch="$(git rev-parse --abbrev-ref HEAD)"
  local into_name="${INTO_NAME:-$current_branch}"
  # We could use --merges below, but we want to match our fake empty merges too when enabled.
  local merges="$(git log --pretty=%s --fixed-strings --since "$_var_merge_lookback" --grep "$TAG" --grep "Merge tag")"
  local begin_after=
  local remote

  if [ $_var_resume_from_last_merge -eq 1 ]; then
    # Check chipset remotes in reverse merge order to determine where we left off.
    for remote in $(printf "%s\n" ${_chipset_remotes[$CHIPSET]} | tac); do
      local remote_url="${_remote_urls[$remote]}"
      local expected_commit_prefix="Merge tag '$TAG' of $remote_url"
      if printf "%s\n" "$merges" | grep -qF "$expected_commit_prefix"; then
        begin_after="$remote"
        echo "Found merge of $remote, so will skip ahead to merging repos that follow..." >&2
        break
      fi
    done
  fi

  for remote in ${_chipset_remotes[$CHIPSET]}; do
    if [ $_var_resume_from_last_merge -eq 1 ] && [ -n "$begin_after" ]; then
      if [ "$remote" != "$begin_after" ]; then
        continue
      else
        begin_after=
      fi
      continue
    fi

    local remote_url="${_remote_urls[$remote]}"
    local expected_commit_prefix="Merge tag '$TAG' of $remote_url"
    if printf "%s\n" "$merges" | grep -qF "$expected_commit_prefix"; then
      echo "Skipping already-merged '$remote/$TAG'." >&2
      continue
    fi
    local subtree="${_subtrees[$remote]:-}"
    echo "Merging $remote/$TAG for $remote in subtree '$subtree'..." >&2
    local -a subtree_arg=()
    if [ -n "$subtree" ]; then
      subtree_arg=(-X "subtree=$subtree")
    fi
    git merge "${subtree_arg[@]}" "${edit_arg[@]}" $_var_merge_git_arguments \
        -m "$expected_commit_prefix into $into_name"$'\n' \
        "$remote/$TAG" || {
      local err=$?
      echo "Failed to merge $remote/$TAG with error $err." >&2
      return $err
    }

    local last_commit_title="$(git log -1 --pretty=%s)"
    case "$last_commit_title" in
      "$expected_commit_prefix"*)
        if [ $_var_push_merge_review -eq 1 ]; then
          git push-merge-review "$_var_push_remote" HEAD "$PUSH_REMOTE_BRANCH" || return $?
        fi
        ;;
      *)
        if [ $_var_merge_empty -eq 1 ]; then
          # Assume no merge because it was already up to date.
          git commit --allow-empty -m "$expected_commit_prefix into $into_name"$'\n\n'"Already up to date." || return $?
        fi
        ;;
    esac
  done
}



### EXECUTE MAIN ###
main "$@" || exit $?
exit 0
