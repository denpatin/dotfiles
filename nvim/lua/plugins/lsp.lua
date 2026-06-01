return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        erlangls = {
          mason = false,
        },
        crystalline = {
          mason = false,
        },
      },
    },
  },
}
