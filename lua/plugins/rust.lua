-- Rust tweaks on top of lazyvim.plugins.extras.lang.rust
return {
  -- rustaceanvim manages rust-analyzer itself (do NOT also set it up via lspconfig)
  {
    "mrcjkb/rustaceanvim",
    opts = {
      server = {
        default_settings = {
          ["rust-analyzer"] = {
            -- run clippy instead of check on save
            check = { command = "clippy", extraArgs = { "--no-deps" } },
            cargo = {
              -- needed so Bevy's feature-gated code resolves
              allFeatures = false,
              buildScripts = { enable = true },
            },
            procMacro = { enable = true },
            -- Bevy is large; keep the analysis responsive
            files = { excludeDirs = { "target" } },
          },
        },
      },
    },
  },

  -- crates.nvim: versions + features inline in Cargo.toml
  {
    "saecki/crates.nvim",
    opts = {
      completion = { crates = { enabled = true } },
      lsp = { enabled = true, actions = true, completion = true, hover = true },
    },
  },
}
