local M = {}

---Check if gh CLI is available
---@return boolean
function M.is_available()
  return vim.fn.executable("gh") == 1
end

---Check if authenticated with GitHub
---@return boolean
function M.is_authenticated()
  local result = vim.fn.system("gh auth status 2>&1")
  return vim.v.shell_error == 0
end

---Get current repo info from git remote
---@return { owner: string, repo: string }|nil
function M.get_repo_info()
  local result = vim.fn.system("gh repo view --json owner,name -q '.owner.login + \"/\" + .name'")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local parts = vim.split(vim.trim(result), "/")
  if #parts ~= 2 then
    return nil
  end
  return { owner = parts[1], repo = parts[2] }
end

---List open PRs
---@param opts? { limit?: number, state?: string }
---@return table[]|nil
function M.list_prs(opts)
  opts = opts or {}
  local limit = opts.limit or 30
  local state = opts.state or "open"

  local cmd = string.format(
    "gh pr list --limit %d --state %s --json number,title,author,headRefName,baseRefName,createdAt,isDraft",
    limit,
    state
  )
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local ok, prs = pcall(vim.json.decode, result)
  if not ok then
    return nil
  end
  return prs
end

---Get PR details
---@param number number PR number
---@return PRContext|nil
function M.get_pr(number)
  local cmd = string.format(
    "gh pr view %d --json number,title,body,author,baseRefName,baseRefOid,headRefName,headRefOid,url,additions,deletions,changedFiles",
    number
  )
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local ok, pr = pcall(vim.json.decode, result)
  if not ok then
    return nil
  end

  local repo_info = M.get_repo_info()
  if not repo_info then
    return nil
  end

  return {
    number = pr.number,
    owner = repo_info.owner,
    repo = repo_info.repo,
    title = pr.title,
    body = pr.body,
    author = pr.author.login,
    base_ref = pr.baseRefName,
    head_ref = pr.headRefName,
    base_sha = pr.baseRefOid,
    head_sha = pr.headRefOid,
    url = pr.url,
    additions = pr.additions,
    deletions = pr.deletions,
    changed_files = pr.changedFiles,
    merge_base = nil, -- filled in by get_merge_base
  }
end

---Checkout PR branch (legacy - switches branch)
---@param number number PR number
---@return boolean success
---@return string? error
function M.checkout_pr(number)
  local result = vim.fn.system(string.format("gh pr checkout %d 2>&1", number))
  if vim.v.shell_error ~= 0 then
    return false, vim.trim(result)
  end
  return true, nil
end

---Fetch PR refs without checking out (keeps current branch)
---@param number number PR number
---@return boolean success
---@return string? error
function M.fetch_pr(number)
  -- Fetch the PR head ref so we have the commits locally
  local cmd = string.format("git fetch origin pull/%d/head 2>&1", number)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return false, vim.trim(result)
  end
  return true, nil
end

---Get merge-base between two refs
---@param base string Base ref
---@param head string Head ref
---@return string|nil
function M.get_merge_base(base, head)
  local cmd = string.format("git merge-base %s %s", vim.fn.shellescape(base), vim.fn.shellescape(head))
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

---Fetch review threads for a PR using GraphQL
---@param number number PR number
---@return GitHubThread[]|nil
function M.get_review_threads(number)
  local repo_info = M.get_repo_info()
  if not repo_info then
    return nil
  end

  local query = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          path
          line
          startLine
          diffSide
          isResolved
          isOutdated
          comments(first: 50) {
            nodes {
              id
              body
              author { login }
              createdAt
              reactionGroups {
                content
                users { totalCount }
              }
            }
          }
        }
      }
    }
  }
}
]]

  local request_body = vim.json.encode({
    query = query,
    variables = {
      owner = repo_info.owner,
      repo = repo_info.repo,
      number = number,
    },
  })

  local tmpfile = "/tmp/review_nvim_graphql.json"
  local f = io.open(tmpfile, "w")
  if not f then
    return nil
  end
  f:write(request_body)
  f:close()

  local cmd = string.format("gh api graphql --input %s 2>&1", vim.fn.shellescape(tmpfile))
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local ok, data = pcall(vim.json.decode, result)
  if not ok or not data.data then
    return nil
  end

  local threads = {}
  local nodes = data.data.repository.pullRequest.reviewThreads.nodes or {}

  for _, node in ipairs(nodes) do
    local comments = {}
    for _, c in ipairs(node.comments.nodes or {}) do
      local reactions = {}
      for _, rg in ipairs(c.reactionGroups or {}) do
        if rg.users.totalCount > 0 then
          reactions[rg.content] = rg.users.totalCount
        end
      end
      table.insert(comments, {
        id = c.id,
        author = c.author and c.author.login or "ghost",
        body = c.body,
        created_at = c.createdAt,
        reactions = reactions,
      })
    end

    table.insert(threads, {
      id = node.id,
      path = node.path,
      line = node.line,
      start_line = node.startLine,
      side = node.diffSide,
      is_resolved = node.isResolved,
      is_outdated = node.isOutdated,
      comments = comments,
    })
  end

  return threads
end

---Submit a review with inline thread comments
---@param pr_id string PR node ID
---@param event "APPROVE"|"REQUEST_CHANGES"|"COMMENT"
---@param body? string Overall review body
---@param threads? { path: string, line: number, side?: string, body: string }[]
---@return boolean success
---@return string? error
function M.submit_review(pr_id, event, body, threads)
  local mutation = [[
mutation($input: AddPullRequestReviewInput!) {
  addPullRequestReview(input: $input) {
    pullRequestReview {
      id
      state
    }
  }
}
]]

  local input = {
    pullRequestId = pr_id,
    event = event,
  }
  if body and body ~= "" then
    input.body = body
  end
  if threads and #threads > 0 then
    input.threads = threads
  end

  local request_body = vim.json.encode({
    query = mutation,
    variables = { input = input },
  })

  local tmpfile = "/tmp/review_nvim_submit.json"
  local f = io.open(tmpfile, "w")
  if not f then
    return false, "Failed to create temp file"
  end
  f:write(request_body)
  f:close()

  local cmd = string.format("gh api graphql --input %s 2>&1", vim.fn.shellescape(tmpfile))
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return false, vim.trim(result)
  end

  return true, nil
end

---Get PR node ID (needed for mutations)
---@param number number PR number
---@return string|nil
function M.get_pr_node_id(number)
  local cmd = string.format("gh pr view %d --json id -q .id", number)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

---Start a new review thread on a specific line or range
---Creates thread then immediately submits it so it's visible right away
---@param pr_id string PR node ID
---@param path string File path relative to repo root
---@param line number Line number in the file
---@param body string Comment body
---@param start_line? number Start line for multi-line comments
---@param side? "LEFT"|"RIGHT" Diff side (default RIGHT for new changes)
---@return boolean success
---@return string? error
function M.add_review_thread(pr_id, path, line, body, start_line, side)
  -- Validate inputs
  if not pr_id or pr_id == "" then
    return false, "PR ID is empty"
  end
  if not path or path == "" then
    return false, "File path is empty"
  end
  if not line or line < 1 then
    return false, "Invalid line number"
  end
  if not body or body == "" then
    return false, "Comment body is empty"
  end

  -- Step 1: Create thread with addPullRequestReviewThread (creates pending)
  local create_mutation = [[mutation($input: AddPullRequestReviewThreadInput!) { addPullRequestReviewThread(input: $input) { thread { id } } }]]

  local input = {
    pullRequestId = pr_id,
    path = path,
    line = line,
    side = side or "RIGHT",
    body = body,
  }

  -- Add startLine for multi-line comments
  if start_line and start_line ~= line then
    input.startLine = start_line
    input.startSide = side or "RIGHT"
  end

  local request_body = vim.json.encode({
    query = create_mutation,
    variables = { input = input },
  })

  local tmpfile = "/tmp/review_nvim_graphql.json"
  local f = io.open(tmpfile, "w")
  if not f then
    return false, "Failed to create temp file"
  end
  f:write(request_body)
  f:close()

  local cmd = string.format("gh api graphql --input %s 2>&1", vim.fn.shellescape(tmpfile))
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, vim.trim(result)
  end

  -- Step 2: Submit the pending review immediately with submitPullRequestReview
  local submit_mutation = [[mutation($input: SubmitPullRequestReviewInput!) { submitPullRequestReview(input: $input) { pullRequestReview { id } } }]]

  local submit_input = {
    pullRequestId = pr_id,
    event = "COMMENT",
  }

  local submit_body = vim.json.encode({
    query = submit_mutation,
    variables = { input = submit_input },
  })

  f = io.open(tmpfile, "w")
  if not f then
    return false, "Failed to create temp file for submit"
  end
  f:write(submit_body)
  f:close()

  result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    -- Thread was created but submit failed - still return success
    -- The thread exists, just pending
    return true, nil
  end

  return true, nil
end

---Update a comment body
---@param comment_id string Comment node ID
---@param body string New body text
---@return boolean success
---@return string? error
function M.update_comment(comment_id, body)
  local mutation = [[
mutation($input: UpdatePullRequestReviewCommentInput!) {
  updatePullRequestReviewComment(input: $input) {
    pullRequestReviewComment {
      id
    }
  }
}
]]

  local variables = vim.json.encode({
    input = {
      pullRequestReviewCommentId = comment_id,
      body = body,
    },
  })

  local cmd = string.format(
    "gh api graphql -f query=%s -f variables=%s",
    vim.fn.shellescape(mutation),
    vim.fn.shellescape(variables)
  )

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return false, vim.trim(result)
  end

  return true, nil
end

---Delete a comment
---@param comment_id string Comment node ID
---@return boolean success
---@return string? error
function M.delete_comment(comment_id)
  local mutation = [[
mutation($input: DeletePullRequestReviewCommentInput!) {
  deletePullRequestReviewComment(input: $input) {
    pullRequestReviewComment {
      id
    }
  }
}
]]

  local variables = vim.json.encode({
    input = {
      id = comment_id,
    },
  })

  local cmd = string.format(
    "gh api graphql -f query=%s -f variables=%s",
    vim.fn.shellescape(mutation),
    vim.fn.shellescape(variables)
  )

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return false, vim.trim(result)
  end

  return true, nil
end

---Add a reaction to a comment
---@param comment_id string Comment node ID
---@param reaction string Reaction type (THUMBS_UP, THUMBS_DOWN, LAUGH, HOORAY, CONFUSED, HEART, ROCKET, EYES)
---@return boolean success
---@return string? error
function M.add_reaction(comment_id, reaction)
  local mutation = [[
mutation($input: AddReactionInput!) {
  addReaction(input: $input) {
    reaction {
      content
    }
  }
}
]]

  local variables = vim.json.encode({
    input = {
      subjectId = comment_id,
      content = reaction,
    },
  })

  local cmd = string.format(
    "gh api graphql -f query=%s -f variables=%s",
    vim.fn.shellescape(mutation),
    vim.fn.shellescape(variables)
  )

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return false, vim.trim(result)
  end

  return true, nil
end

---Get current authenticated user
---@return string|nil
function M.get_current_user()
  local cmd = "gh api user -q .login"
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

return M
