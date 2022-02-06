---@param client NeotestClient
local consumer_name = "neotest-summary"
local config = require("neotest.config")
---@param client NeotestClient
return function(client)
  local RenderState = require("neotest.consumers.summary.render")
  local SummaryComponent = require("neotest.consumers.summary.component")
  local async = require("plenary.async")

  local buf_name = "Neotest Summary"
  local summary_buf

  local function create_buf()
    if summary_buf then
      return summary_buf
    end

    summary_buf = async.api.nvim_create_buf(false, true)
    local options = {
      modifiable = false,
      filetype = "neotest-summary",
    }
    for name, value in pairs(options) do
      async.api.nvim_buf_set_option(summary_buf, name, value)
    end
    async.api.nvim_buf_set_name(summary_buf, buf_name)
    return summary_buf
  end

  local function is_open()
    return summary_buf and async.fn.bufwinnr(summary_buf) ~= -1
  end

  local function open_window(buf)
    local cur_win = async.api.nvim_get_current_win()
    vim.cmd([[botright vsplit | vertical resize 50]])
    local win = async.api.nvim_get_current_win()
    local options = {
      relativenumber = false,
      number = false,
      winfixwidth = true,
    }
    for name, value in pairs(options) do
      async.api.nvim_win_set_option(win, name, value)
    end
    async.api.nvim_win_set_buf(win, buf)
    async.api.nvim_set_current_win(cur_win)
  end

  local components = {}

  local render = function(expanded)
    if not is_open() then
      return
    end
    local render_state = RenderState.new(config.summary)
    local cwd = async.fn.getcwd()
    for _, adapter_id in ipairs(client:get_adapters()) do
      local tree = client:get_position(nil, { adapter = adapter_id })
      render_state:write(adapter_id .. "\n", { group = config.highlights.adapter_name })
      if tree:data().path ~= cwd then
        local root_dir = async.fn.fnamemodify(tree:data().path, ":.")
        render_state:write(root_dir .. "\n", { group = config.highlights.dir })
      end
      components[adapter_id] = components[adapter_id] or SummaryComponent(client, adapter_id)
      components[adapter_id]:render(render_state, tree, expanded or {})
      render_state:write("\n")
    end
    if render_state:length() > 1 then
      render_state:remove_line()
      render_state:remove_line()
    else
      render_state:write("No tests found")
    end
    render_state:render_buffer(summary_buf)
  end

  local listener = function()
    render()
  end
  client.listeners.discover_positions[consumer_name] = listener
  client.listeners.run[consumer_name] = listener
  client.listeners.results[consumer_name] = function(adapter_id, results)
    if not config.summary.expand_errors then
      render()
    end
    local expanded = {}
    for pos_id, result in pairs(results) do
      if
        result.status == "failed"
        and client:get_position(pos_id, { refresh = false, adapter = adapter_id })
        and #client:get_position(pos_id, { adapter = adapter_id }):children() > 0
      then
        expanded[pos_id] = true
      end
    end
    render(expanded)
  end
  local function expand(pos_id, recursive)
    local tree = client:get_position(pos_id)
    if not tree then
      return
    end
    local expanded = {}
    if recursive then
      for _, node in tree:iter_nodes() do
        if #node:children() > 0 then
          expanded[node:data().id] = true
        end
      end
    else
      expanded[pos_id] = true
    end
    for parent in tree:iter_parents() do
      expanded[parent:data().id] = true
    end
    render(expanded)
  end

  if config.summary.follow then
    client.listeners.test_file_focused[consumer_name] = function(_, file_path)
      expand(file_path, true)
    end
  end
  local function open()
    async.run(function()
      client:ensure_started()
    end)
    create_buf()
    open_window(summary_buf)
  end

  return {
    render = render,
    toggle = function()
      async.run(function()
        if is_open() then
          local win = async.fn.win_getid(async.fn.bufwinnr(summary_buf))
          async.api.nvim_win_close(win, true)
        else
          open()
          render()
        end
      end)
    end,
    expand = function(pos_id, recursive)
      async.run(function()
        expand(pos_id, recursive)
      end)
    end,
  }
end
