return {
  "mfussenegger/nvim-lint",
  opts = function(_, opts)
    local markdownlint = require("lint").linters["markdownlint-cli2"]
    markdownlint.args = {
      "--config",
      vim.json.encode({
        config = {
          MD013 = false,
        },
      }),
    }
  end,
}
