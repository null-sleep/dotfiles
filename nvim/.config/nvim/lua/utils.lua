local M = {}

-- Build a GitHub URL from a "owner/repo" string
function M.gh(repo)
  return 'https://github.com/' .. repo
end

return M
