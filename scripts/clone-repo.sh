#!/usr/bin/env zsh
# shellcheck disable=2154
#───────────────────────────────────────────────────────────────────────────────

https_url="$1"
source_repo=$(echo "$https_url" | sed -E 's_.*github.com/([^/?]*/[^/?]*).*_\1_')
reponame=$(echo "$source_repo" | cut -d '/' -f2)
owner=$(echo "$source_repo" | cut -d '/' -f1)
ssh_url="git@github.com:$source_repo"

[[ ! -e "$local_repo_folder" ]] && mkdir -p "$local_repo_folder"
cd "$local_repo_folder" || return 1

#───────────────────────────────────────────────────────────────────────────────
# CLONE

# if multiple repos of same name, add owner to directory name of both the
# existing and the to-be-cloned repo (see https://github.com/chrisgrieser/gitfred/issues/5)
# (uses `__` as separator, since that string normally does not occur in reponames)
clone_dir="$reponame"
if [[ -d "$reponame" ]]; then
	clone_dir="${owner}__$reponame"
	# rename existing repo
	owner_of_existing_repo=$(git -C "$reponame" remote --verbose | tail -n1 | sed -Ee 's|.*:(.*)/.*|\1|')
	mv "$reponame" "${owner_of_existing_repo}__$reponame"
elif [[ -n $(find . -type directory -name "*__$reponame") ]] ; then
	clone_dir="${owner}__$reponame"
fi

# clone with depth
if [[ $clone_depth == "0" ]]; then
	msg=$(git clone "$ssh_url" --no-single-branch --no-tags "$clone_dir" 2>&1)
else
	# WARN depth=1 is dangerous, as amending such a commit does result in a
	# new commit without parent, effectively destroying git history (!!)
	[[ $clone_depth == "1" ]] && clone_depth=2
	msg=$(git clone "$ssh_url" --depth="$clone_depth" --no-single-branch --no-tags "$clone_dir" 2>&1)
fi

success=$?
if [[ $success -ne 0 ]]; then
	echo "ERROR: Clone failed. $msg"
	return 1
fi

# Open in terminal via Alfred
echo -n "$local_repo_folder/$clone_dir"

cd "$clone_dir" || return 1

#───────────────────────────────────────────────────────────────────────────────

# POST CLONE ACTIONS
if [[ -n "$branch_on_clone" ]]; then
	# `git switch` fails silently if the branch does not exist
	git switch "$branch_on_clone" &> /dev/null
fi

if [[ "$restore_mtime" == "1" ]]; then
	# https://stackoverflow.com/a/36243002/22114136
	git ls-tree -r -t --full-name --name-only HEAD | while read -r file; do
		timestamp=$(git log --pretty=format:%cd --date=format:%Y%m%d%H%M.%S -1 HEAD -- "$file")
		touch -t "$timestamp" "$file"
	done
fi

#───────────────────────────────────────────────────────────────────────────────
# FORKING

# INFO Alfred stores checkbox settings as `"1"` or `"0"`, and variables in stringified form.
if [[ "$ownerOfRepo" != "true" && "$fork_on_clone" == "1" ]] ||
	[[ "$clonedViaHotkey" == "true" && "$fork_on_clone_via_hotkey" == "1" ]]; then

	if [[ ! -x "$(command -v gh)" ]]; then
		echo "ERROR: \`gh\` not installed." 
		return 1
	fi

	gh repo fork --remote=false

	if [[ "$setup_remotes_on_fork" == "1" ]] ; then
		git remote rename origin upstream
		git remote add origin "git@github.com:$github_username/$reponame.git"
		gh repo set-default "$source_repo" # where `gh` sends PRs to
	fi

	if [[ -n "$on_fork_branch" ]] ; then 
		git switch --create "$on_fork_branch"
	fi
fi
