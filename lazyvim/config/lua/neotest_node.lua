local lib = require("neotest.lib")

local query = [[
  ((call_expression
    function: (identifier) @func_name (#any-of? @func_name "test" "it")
    arguments: (arguments (string (string_fragment) @test.name) [(arrow_function) (function_expression)])
  ) @test.definition)

  ((call_expression
    function: (identifier) @func_name (#eq? @func_name "describe")
    arguments: (arguments (string (string_fragment) @namespace.name) [(arrow_function) (function_expression)])
  ) @namespace.definition)
]]

local root = lib.files.match_root_pattern("package.json")

local function manifest(file)
  local directory = root(file)
  local handle = directory and io.open(directory .. "/package.json", "r")
  if not handle then
    return nil
  end
  local text = handle:read("*a")
  handle:close()
  return text
end

local function tap(output)
  local handle = output and io.open(output, "r")
  if not handle then
    return {}
  end
  local text = handle:read("*a")
  handle:close()

  local tests, name, section = {}, nil, nil

  for line in vim.gsplit(text, "\n", { plain = true }) do
    line = line:gsub("\27%[[%d;]*m", ""):gsub("\r", "")

    local failed = line:match("^%s*not ok %d+ %- (.+)$")
    local passed = line:match("^%s*ok %d+ %- (.+)$")
    local key = line:match("^%s*([%w_]+):")

    if failed or passed then
      name = failed or passed
      section = nil
      tests[name] = { status = failed and "failed" or "passed", message = {} }
    elseif line:match("^%s*%.%.%.%s*$") or line:match("^%s*%-%-%-%s*$") then
      section = nil
    elseif key and tests[name or ""] then
      section = key
      local inline = line:match("^%s*error:%s*(.-)%s*$")
      if inline and inline ~= "" and inline ~= "|-" and inline ~= "|" then
        table.insert(tests[name].message, inline)
        section = nil
      end
    elseif name and section == "error" and line:match("%S") then
      table.insert(tests[name].message, (line:gsub("^%s+", "")))
    elseif name and section == "stack" and not tests[name].line then
      tests[name].line = tonumber(line:match(":(%d+):%d+%)%s*$"))
    end
  end

  return tests
end

return {
  name = "neotest-node",
  root = root,
  filter_dir = function(name)
    return name ~= "node_modules" and name ~= "dist"
  end,
  is_test_file = function(file)
    if not file:match("%.test%.[cm]?[jt]sx?$") and not file:match("%.spec%.[cm]?[jt]sx?$") then
      return false
    end
    local text = manifest(file)
    return text ~= nil and not text:find("vitest", 1, true) and not text:find("jest", 1, true)
  end,
  discover_positions = function(path)
    return lib.treesitter.parse_positions(path, query)
  end,
  build_spec = function(args)
    local position = args.tree:data()
    return {
      command = { "node", "--test", "--test-reporter=tap", position.path },
      cwd = root(position.path),
    }
  end,
  results = function(_, result, tree)
    local tests = tap(result.output)
    local results = {}

    for _, node in tree:iter_nodes() do
      local position = node:data()
      local found = position.type == "test" and tests[position.name]
      if found then
        results[position.id] = {
          status = found.status,
          output = result.output,
          errors = found.status == "failed"
              and { { message = table.concat(found.message, "\n"), line = found.line and found.line - 1 } }
            or nil,
        }
      end
    end

    return results
  end,
}
