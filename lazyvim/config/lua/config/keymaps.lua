local function focused_explorer()
  local explorer = Snacks.picker.get({ source = "explorer" })[1]
  if explorer and explorer:is_focused() then
    return explorer
  end
end

local function explorer_selection()
  local explorer = focused_explorer()
  if not explorer then
    return nil, nil
  end

  local item = explorer:current()
  if not item or not item.file or vim.fn.isdirectory(item.file) == 1 then
    return nil, nil
  end

  return vim.fn.fnamemodify(item.file, ":p"), explorer
end

local function runner(file, filetype)
  local directory = vim.fn.fnamemodify(file, ":h")
  local escaped_file = vim.fn.shellescape(file)

  if filetype == "sh" or filetype == "bash" or filetype == "zsh" then
    return directory, "bash " .. escaped_file
  end

  if filetype == "python" then
    local root = vim.fs.root(file, { "requirements.txt", "pyproject.toml", "setup.py", "setup.cfg" })
    if root then
      return root, "PYTHONPATH=" .. vim.fn.shellescape(root) .. " python3 " .. escaped_file
    end
    return directory, "python3 " .. escaped_file
  end

  if filetype == "rust" then
    local root = vim.fs.root(file, "Cargo.toml")
    if root then
      return root, "cargo run"
    end
    return directory, "rustc " .. escaped_file .. " -o /tmp/nvim-rust-runner && /tmp/nvim-rust-runner"
  end

  if filetype == "go" then
    if vim.fs.root(file, "go.mod") then
      return directory, "go run ."
    end
    return directory, "go run " .. escaped_file
  end

  if filetype == "typescript" or filetype == "typescriptreact" then
    local root = vim.fs.root(file, "tsconfig.json")
    if root then
      return root, "tsgo --noEmit && bun run " .. escaped_file
    end
    return directory, "tsgo --noEmit " .. escaped_file .. " && bun run " .. escaped_file
  end
end

local function run_target()
  local selected = explorer_selection()
  if selected then
    return selected, vim.filetype.match({ filename = selected }) or ""
  end

  if vim.bo.buftype ~= "" or vim.fn.expand("%") == "" then
    return nil, nil
  end

  vim.cmd("write")
  return vim.fn.expand("%:p"), vim.bo.filetype
end

local function run_code()
  local file, filetype = run_target()

  if not file then
    vim.notify("No file to run", vim.log.levels.ERROR)
    return
  end

  local directory, command = runner(file, filetype)

  if not command then
    vim.notify("No runner for " .. filetype, vim.log.levels.ERROR)
    return
  end

  local source_window = vim.api.nvim_get_current_win()
  local runner_window

  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.w[window].code_runner then
      runner_window = window
      break
    end
  end

  if runner_window then
    local previous_buffer = vim.api.nvim_win_get_buf(runner_window)
    local terminal_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(runner_window, terminal_buffer)
    pcall(vim.api.nvim_buf_delete, previous_buffer, { force = true })
    vim.api.nvim_set_current_win(runner_window)
  else
    vim.cmd("botright 12new")
    runner_window = vim.api.nvim_get_current_win()
    vim.w[runner_window].code_runner = true
  end

  local runner_job = vim.fn.termopen(vim.o.shell, { cwd = directory })
  vim.fn.chansend(runner_job, "cd " .. vim.fn.shellescape(directory) .. " && " .. command .. "\n")
  vim.api.nvim_win_set_height(runner_window, 12)
  vim.api.nvim_set_current_win(source_window)
end

local function toggle_explorer()
  local explorer = Snacks.picker.get({ source = "explorer" })[1]

  if not explorer then
    Snacks.explorer({ cwd = LazyVim.root() })
    return
  end

  if explorer:is_focused() then
    explorer:close()
    return
  end

  explorer:focus("list")
end

local function explorer_create(kind)
  local explorer = focused_explorer()
  if not explorer then
    return
  end

  Snacks.input({ prompt = kind == "directory" and "New folder" or "New file" }, function(name)
    if not name or name:match("^%s*$") then
      return
    end

    local path = vim.fs.normalize(explorer:dir() .. "/" .. name)

    if vim.uv.fs_stat(path) then
      vim.notify(path .. " already exists", vim.log.levels.ERROR)
      return
    end

    local directory = kind == "directory" and path or vim.fs.dirname(path)
    vim.fn.mkdir(directory, "p")

    if kind == "file" then
      io.open(path, "w"):close()
    end

    local tree = require("snacks.explorer.tree")
    tree:open(directory)
    tree:refresh(directory)
    require("snacks.explorer.actions").update(explorer, { target = path })
  end)
end

local function open_in_chrome(file)
  local job = vim.fn.jobstart({ "open", "-a", "Google Chrome", file }, { detach = true })
  if job <= 0 then
    vim.notify("Could not open Google Chrome", vim.log.levels.ERROR)
  end
end

local function render_html()
  local file, explorer = explorer_selection()

  if not file then
    if vim.bo.buftype ~= "" or vim.fn.expand("%") == "" then
      vim.notify("No file selected", vim.log.levels.ERROR)
      return
    end
    vim.cmd("write")
    file = vim.fn.expand("%:p")
  end

  local extension = vim.fn.fnamemodify(file, ":e"):lower()

  if extension == "md" or extension == "markdown" then
    if explorer then
      explorer:close()
      vim.cmd("edit " .. vim.fn.fnameescape(file))
    end
    vim.cmd("RenderMarkdown toggle")
    return
  end

  if extension ~= "html" and extension ~= "htm" then
    vim.notify("File is not HTML or Markdown", vim.log.levels.ERROR)
    return
  end

  open_in_chrome(file)
end

local function find_project_files()
  Snacks.picker.files({ cwd = LazyVim.root(), hidden = true })
end

local function open_project_terminal()
  Snacks.terminal.focus(nil, { cwd = LazyVim.root() })
end

local function switch_open_file()
  Snacks.picker.buffers({ unloaded = false, hidden = false, nofile = false })
end

local function goto_function()
  Snacks.picker.treesitter({
    filter = { default = { "Function", "Method" } },
  })
end

local function goto_definition()
  vim.lsp.buf.definition()
end

local function find_references()
  Snacks.picker.lsp_references()
end

local function project_grep()
  Snacks.picker.grep({ cwd = LazyVim.root() })
end

local function rename_symbol()
  vim.lsp.buf.rename()
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "n", false)
end

local function show_navigation_help()
  local moves = {
    { key = "0", action = "Go to beginning of line", run = "0" },
    { key = "^", action = "Go to first non-blank of line", run = "^" },
    { key = "$", action = "Go to end of line", run = "$" },
    { key = "gg", action = "Go to first line of file", run = "gg" },
    { key = "G", action = "Go to last line of file", run = "G" },
    { key = "w", action = "Jump to next word", run = "w" },
    { key = "b", action = "Jump to previous word", run = "b" },
    { key = "e", action = "Jump to end of word", run = "e" },
    { key = "{", action = "Jump to previous paragraph", run = "{" },
    { key = "}", action = "Jump to next paragraph", run = "}" },
    { key = "%", action = "Jump to matching bracket", run = "%" },
    { key = "H", action = "Move to top of screen", run = "H" },
    { key = "M", action = "Move to middle of screen", run = "M" },
    { key = "L", action = "Move to bottom of screen", run = "L" },
    { key = "Ctrl+d", action = "Scroll half page down", run = "<C-d>" },
    { key = "Ctrl+u", action = "Scroll half page up", run = "<C-u>" },
    { key = "*", action = "Search word under cursor", run = "*" },
    { key = "``", action = "Jump back to previous position", run = "``" },
  }

  Snacks.picker.select(moves, {
    prompt = "Navigation",
    format_item = function(item)
      return item.key .. "  " .. item.action
    end,
  }, function(item)
    if item then
      feed(item.run)
    end
  end)
end

local function show_custom_shortcuts()
  local shortcuts = {
    { key = "Option+1", action = "Run selected or current file", run = run_code },
    { key = "Option+2", action = "Toggle file explorer", run = toggle_explorer },
    { key = "Option+3", action = "Find project files", run = find_project_files },
    { key = "Option+4", action = "Open HTML in Chrome / Toggle Markdown render", run = render_html },
    { key = "Option+5", action = "Focus project terminal", run = open_project_terminal },
    { key = "Option+6", action = "Go to function", run = goto_function },
    { key = "Option+7", action = "Go to definition", run = goto_definition },
    { key = "Option+8", action = "Find references", run = find_references },
    { key = "Option+9", action = "Search project text", run = project_grep },
    { key = "Option+0", action = "Rename symbol", run = rename_symbol },
    { key = "Option+E", action = "Switch open file", run = switch_open_file },
    { key = "Option+/", action = "Show navigation help", run = show_navigation_help },
    { key = "Option+\\", action = "Show custom shortcuts", run = show_custom_shortcuts },
  }

  Snacks.picker.select(shortcuts, {
    prompt = "Custom Option Shortcuts",
    format_item = function(item)
      return item.key .. "  " .. item.action
    end,
  }, function(item)
    if item and item.run then
      item.run()
    end
  end)
end

vim.keymap.set("n", "<F1>", run_code, { silent = true })
vim.keymap.set("n", "<M-1>", run_code, { silent = true, desc = "Run current file" })
vim.keymap.set("n", "<M-2>", toggle_explorer, { silent = true, desc = "Toggle file explorer" })
vim.keymap.set("n", "<M-3>", find_project_files, { silent = true, desc = "Find project files" })
vim.keymap.set("n", "£", find_project_files, { silent = true, desc = "Find project files" })
vim.keymap.set("n", "<M-4>", render_html, { silent = true, desc = "Open HTML in Chrome / Toggle Markdown render" })
vim.keymap.set("n", "¢", render_html, { silent = true, desc = "Open HTML in Chrome / Toggle Markdown render" })
vim.keymap.set({ "n", "t" }, "<M-5>", open_project_terminal, { silent = true, desc = "Focus project terminal" })
vim.keymap.set({ "n", "t" }, "∞", open_project_terminal, { silent = true, desc = "Focus project terminal" })
vim.keymap.set("n", "<M-6>", goto_function, { silent = true, desc = "Go to function" })
vim.keymap.set("n", "§", goto_function, { silent = true, desc = "Go to function" })
vim.keymap.set("n", "<M-7>", goto_definition, { silent = true, desc = "Go to definition" })
vim.keymap.set("n", "¶", goto_definition, { silent = true, desc = "Go to definition" })
vim.keymap.set("n", "<M-8>", find_references, { silent = true, desc = "Find references" })
vim.keymap.set("n", "<M-9>", project_grep, { silent = true, desc = "Search project text" })
vim.keymap.set("n", "<M-0>", rename_symbol, { silent = true, desc = "Rename symbol" })
vim.keymap.set("n", "<M-e>", switch_open_file, { silent = true, desc = "Switch open file" })
vim.keymap.set("n", "´", switch_open_file, { silent = true, desc = "Switch open file" })
vim.keymap.set("n", "<M-Bslash>", show_custom_shortcuts, { silent = true, desc = "Show custom shortcuts" })
vim.keymap.set("n", "«", show_custom_shortcuts, { silent = true, desc = "Show custom shortcuts" })
vim.keymap.set("n", "<M-/>", show_navigation_help, { silent = true, desc = "Show navigation help" })
vim.keymap.set("n", "÷", show_navigation_help, { silent = true, desc = "Show navigation help" })

vim.api.nvim_create_user_command("RunFile", run_code, {})

vim.api.nvim_create_user_command("ExplorerCreateFolder", function()
  explorer_create("directory")
end, {})

vim.api.nvim_create_user_command("ExplorerCreateFile", function()
  explorer_create("file")
end, {})

vim.api.nvim_create_autocmd("MenuPopup", {
  group = vim.api.nvim_create_augroup("explorer_popup", { clear = true }),
  callback = function()
    if not focused_explorer() then
      vim.cmd([[silent! aunmenu PopUp.Create\ Folder]])
      vim.cmd([[silent! aunmenu PopUp.Create\ File]])
      return
    end

    vim.cmd([[
      anoremenu 500.10 PopUp.Create\ Folder <cmd>ExplorerCreateFolder<CR>
      anoremenu 500.20 PopUp.Create\ File <cmd>ExplorerCreateFile<CR>
    ]])
  end,
})

vim.cmd([[
  anoremenu PopUp.-custom-sep- <Nop>
  anoremenu PopUp.Run\ File <cmd>RunFile<CR>
  anoremenu PopUp.Go\ to\ Definition <cmd>lua vim.lsp.buf.definition()<CR>
  anoremenu PopUp.Find\ References <cmd>lua vim.lsp.buf.references()<CR>
  anoremenu PopUp.Rename\ Symbol <cmd>lua vim.lsp.buf.rename()<CR>
  anoremenu PopUp.Code\ Action <cmd>lua vim.lsp.buf.code_action()<CR>
  anoremenu PopUp.Format\ Document <cmd>lua vim.lsp.buf.format({ async = true })<CR>
  anoremenu PopUp.Hover\ Docs <cmd>lua vim.lsp.buf.hover()<CR>
  anoremenu PopUp.-custom-sep2- <Nop>
  vnoremenu PopUp.Copy "+y
  vnoremenu PopUp.Cut "+d
  nnoremenu PopUp.Paste "+gP
  vnoremenu PopUp.Paste "+P
  anoremenu PopUp.Select\ All ggVG
]])
