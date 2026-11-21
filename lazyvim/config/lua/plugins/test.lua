local adapters = {}
local started = {}
local elapsed = {}

local function has_testcase(file_path)
  if not vim.endswith(file_path, ".py") then
    return false
  end
  local file = io.open(file_path, "r")
  if not file then
    return false
  end
  local content = file:read("*a")
  file:close()
  return content:match("unittest%.TestCase") ~= nil
end

local function neotest()
  local ok, mod = pcall(require, "neotest")
  return ok and mod or nil
end

local function summarize(message)
  local text = message:gsub("\27%[[%d;]*m", "")
  for line in text:gmatch("[^\n]+") do
    if not line:match("^%s") and not line:match("^Traceback") then
      return line
    end
  end
  return text
end

local report = {
  "^[=%-][=%-][=%-]",
  "^%s",
  "^Traceback ",
  "^Ran %d+ tests? in",
  "^OK",
  "^FAILED",
  "^FAIL: ",
  "^ERROR: ",
  "^%u[%w_%.]*Error",
}

local function noise(line)
  if line == "" or line:match("^[%.FEsux]+$") then
    return true
  end
  for _, pattern in ipairs(report) do
    if line:match(pattern) then
      return true
    end
  end
  return false
end

local function captured(path)
  local file = path and io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  local out = {}
  for line in text:gmatch("[^\n]+") do
    line = line:gsub("\27%[[%d;]*m[%.FEsxu]\27%[0m", ""):gsub("\27%[[%d;]*m", ""):gsub("\r", "")
    if not noise(line) then
      table.insert(out, line)
    end
  end
  if #out == 0 then
    return nil
  end
  return table.concat(out, "\n")
end

local function readable(adapter)
  local results = adapter.results
  adapter.results = function(spec, result, tree)
    local out = results(spec, result, tree)
    local prints = captured(result.output)
    for _, value in pairs(out) do
      for _, err in ipairs(value.errors or {}) do
        err.message = summarize(err.message)
        if prints then
          err.message = err.message .. "\nstdout: " .. prints
        end
      end
    end
    return out
  end
  return adapter
end

local markers = { "requirements.txt", "pyproject.toml", "setup.py", "setup.cfg", "Pipfile", "tox.ini", ".git" }
local source_dirs = { "src", "lib", "app", "source", "tests", "test" }
local venv_dirs = { ".venv", "venv", "env", ".env" }
local venv_bin = vim.uv.os_uname().sysname:match("Windows") and "Scripts" or "bin"
local interpreter = "/opt/homebrew/bin/python3.14"

local function is_dir(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

local function package_base(dir)
  while vim.uv.fs_stat(dir .. "/__init__.py") do
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      return dir
    end
    dir = parent
  end
  return dir
end

local function python_path(dir, root)
  local seen, entries = {}, {}
  local function add(value)
    if value and value ~= "" and not seen[value] then
      seen[value] = true
      table.insert(entries, value)
    end
  end
  add(package_base(dir))
  add(root)
  for _, layout in ipairs(source_dirs) do
    if is_dir(root .. "/" .. layout) then
      add(root .. "/" .. layout)
    end
  end
  for value in (vim.uv.os_getenv("PYTHONPATH") or ""):gmatch("[^:]+") do
    add(value)
  end
  return table.concat(entries, ":")
end

local function executable(path)
  return vim.uv.fs_stat(path) ~= nil and vim.uv.fs_access(path, "X") == true
end

local function venv_python(dir)
  for _, name in ipairs(venv_dirs) do
    local candidate = dir .. "/" .. name .. "/" .. venv_bin .. "/python"
    if executable(candidate) then
      return candidate
    end
  end
  if vim.uv.fs_stat(dir .. "/pyvenv.cfg") and executable(dir .. "/" .. venv_bin .. "/python") then
    return dir .. "/" .. venv_bin .. "/python"
  end
  return nil
end

local current_root = nil

local function root_of(path)
  local dir = is_dir(path) and path or vim.fs.dirname(path)
  return vim.fs.root(path, markers) or dir
end

local function python_command(root)
  for _, name in ipairs({ "VIRTUAL_ENV", "CONDA_PREFIX" }) do
    local active = vim.uv.os_getenv(name)
    if active and executable(active .. "/" .. venv_bin .. "/python") then
      return active .. "/" .. venv_bin .. "/python"
    end
  end
  local dir = current_root or root or vim.uv.cwd()
  local home = vim.uv.os_homedir()
  while dir and dir ~= "/" and dir ~= home do
    local found = venv_python(dir)
    if found then
      return found
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      break
    end
    dir = parent
  end
  if executable(interpreter) then
    return interpreter
  end
  return "python3"
end

local function scoped(path, fn)
  current_root = root_of(path)
  local ok, result = pcall(fn)
  current_root = nil
  if not ok then
    error(result, 0)
  end
  return result
end

local function rooted(adapter)
  local build_spec = adapter.build_spec
  local discover_positions = adapter.discover_positions
  adapter.discover_positions = function(path)
    return scoped(path, function()
      return discover_positions(path)
    end)
  end
  adapter.build_spec = function(args)
    local path = args.tree:data().path
    local spec = scoped(path, function()
      return build_spec(args)
    end)
    if spec then
      local dir = is_dir(path) and path or vim.fs.dirname(path)
      local root = root_of(path)
      spec.cwd = root
      spec.env = vim.tbl_extend("force", spec.env or {}, { PYTHONPATH = python_path(dir, root) })
    end
    return spec
  end
  local filter_dir = adapter.filter_dir
  adapter.filter_dir = function(name, rel_path, root)
    for _, skip in ipairs(venv_dirs) do
      if name == skip then
        return false
      end
    end
    return filter_dir(name, rel_path, root)
  end
  return adapter
end

local function counts(bufnr)
  local nt = neotest()
  if not nt then
    return nil
  end
  local best, score = nil, -1
  for _, id in ipairs(nt.state.adapter_ids()) do
    local c = nt.state.status_counts(id, { buffer = bufnr })
    if c and c.total > 0 then
      local weight = c.passed + c.failed + c.skipped + c.running + c.total
      if weight > score then
        best, score = c, weight
      end
    end
  end
  return best
end

local function is_test_buf(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" or not vim.uv.fs_stat(file) then
    return false
  end
  for _, adapter in ipairs(adapters) do
    if adapter.is_test_file(file) then
      return true
    end
  end
  return false
end

local function when_ready(bufnr, file, tries)
  local nt = neotest()
  if not nt or tries > 20 or not vim.api.nvim_buf_is_valid(bufnr) or nt.watch.is_watching(file) then
    return
  end
  for _, id in ipairs(nt.state.adapter_ids()) do
    if nt.state.positions(id, { buffer = bufnr }) then
      nt.run.run(file)
      nt.watch.watch(file)
      return
    end
  end
  nt.autotest.discover(file)
  vim.defer_fn(function()
    when_ready(bufnr, file, tries + 1)
  end, 500)
end

local function start(bufnr)
  local nt = neotest()
  if not nt or not vim.api.nvim_buf_is_valid(bufnr) or not is_test_buf(bufnr) then
    return
  end
  local file = vim.api.nvim_buf_get_name(bufnr)
  if nt.watch.is_watching(file) or #vim.lsp.get_clients({ bufnr = bufnr }) == 0 then
    return
  end
  when_ready(bufnr, file, 0)
end

local function report()
  local nt = neotest()
  if not nt then
    return
  end
  nt.summary.open()
  nt.output_panel.open()
end

return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/neotest-python",
      "fredrikaverpil/neotest-golang",
      "marilari88/neotest-vitest",
    },
    ft = { "python", "go", "rust", "javascript", "javascriptreact", "typescript", "typescriptreact" },
    keys = {
      { "<M-.>", report, desc = "Test report" },
      { "≥", report, desc = "Test report" },
      { "<leader>tr", function() neotest().run.run() end, desc = "Run nearest test" },
      { "<leader>tf", function() neotest().run.run(vim.fn.expand("%")) end, desc = "Run file tests" },
      { "<leader>tw", function() neotest().watch.toggle(vim.fn.expand("%")) end, desc = "Toggle test watch" },
    },
    config = function()
      adapters = {
        rooted(readable(require("neotest-python")({
          dap = false,
          python = python_command,
          is_test_file = function(file_path)
            return require("neotest-python.base").is_test_file(file_path) or has_testcase(file_path)
          end,
        }))),
        require("neotest-golang"),
        require("neotest-vitest"),
        require("neotest_node"),
        require("rustaceanvim.neotest"),
      }

      require("neotest").setup({
        adapters = adapters,
        consumers = {
          autotest = function(client)
            client.listeners.run = function(_, root_id)
              started[root_id] = vim.uv.hrtime()
            end
            client.listeners.results = function(_, _, partial)
              if partial then
                return
              end
              local now = vim.uv.hrtime()
              for root_id, at in pairs(started) do
                elapsed[root_id] = (now - at) / 1e6
                started[root_id] = nil
              end
            end
            return {
              discover = function(file)
                require("nio").run(function()
                  client:get_position(file, {})
                end)
              end,
            }
          end,
        },
        status = { virtual_text = true },
        output = { open_on_run = false },
        quickfix = { enabled = false },
      })

      vim.api.nvim_create_autocmd({ "LspAttach", "BufWritePost" }, {
        group = vim.api.nvim_create_augroup("neotest_autowatch", { clear = true }),
        callback = function(args)
          vim.defer_fn(function()
            start(args.buf)
          end, 2000)
        end,
      })
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, 1, {
        function()
          local bufnr = vim.api.nvim_get_current_buf()
          local c = counts(bufnr)
          if not c then
            return ""
          end
          if c.running > 0 then
            return string.format("󰑮 %d/%d", c.running, c.total)
          end
          local ms = elapsed[vim.api.nvim_buf_get_name(bufnr)]
          local took = "?"
          if ms then
            took = ms >= 1000 and string.format("%.1fs", ms / 1000) or string.format("%dms", math.floor(ms))
          end
          return string.format("%d/%d in %s", c.passed, c.total, took)
        end,
        cond = function()
          return counts(vim.api.nvim_get_current_buf()) ~= nil
        end,
        color = function()
          local c = counts(vim.api.nvim_get_current_buf())
          if c and c.failed > 0 then
            return { fg = Snacks.util.color("DiagnosticError") }
          end
          return { fg = Snacks.util.color("DiagnosticOk") }
        end,
      })
    end,
  },
}
