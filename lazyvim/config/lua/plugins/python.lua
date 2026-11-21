return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      pyright = {
        settings = {
          python = {
            pythonPath = "/opt/homebrew/bin/python3.14",
            analysis = {
              pythonVersion = "3.14",
            },
          },
        },
      },
    },
  },
}
