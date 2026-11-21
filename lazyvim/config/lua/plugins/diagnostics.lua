local function wrap_line(text, width, out)
  local line = ""
  for word in text:gmatch("%S+") do
    if line == "" then
      line = word
    elseif #line + #word + 1 <= width then
      line = line .. " " .. word
    else
      out[#out + 1] = line
      line = word
    end
  end
  if line ~= "" then
    out[#out + 1] = line
  end
end

local function format(diagnostic)
  local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  local indent = 0
  if diagnostic.bufnr and vim.api.nvim_buf_is_loaded(diagnostic.bufnr) then
    local code = vim.api.nvim_buf_get_lines(diagnostic.bufnr, diagnostic.lnum, diagnostic.lnum + 1, false)[1]
    indent = code and #(code:match("^%s*") or "") or 0
  end
  local width = math.max(30, info.width - info.textoff - indent - 8)

  local message = diagnostic.message
  if diagnostic.source then
    message = diagnostic.source:gsub("%.$", "") .. ": " .. message
  end

  local lines = {}
  for text in (message .. "\n"):gmatch("([^\n]*)\n") do
    if text:match("%S") then
      wrap_line(text, width, lines)
    end
  end
  return table.concat(lines, "\n")
end

return {
  "neovim/nvim-lspconfig",
  opts = {
    diagnostics = {
      virtual_text = false,
      virtual_lines = { current_line = true, format = format },
    },
  },
}
