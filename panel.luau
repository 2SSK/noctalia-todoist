--!nonstrict
-- Todoist panel -- todo list with page tabs, inline add/edit, and page
-- management. All data lives in the "data" service; this panel only reads
-- the published "todos"/"count" state and drives mutations through the
-- "command" channel.

local PANEL_ID = "2SSK/todoist:panel"

local view = "todos" -- "todos" | "pages"
local editingId = nil -- id of todo being edited, or nil
local editBuffers = {} -- todo.id -> live text while editing (from onChange)
local editingPageId = nil -- id of page being renamed, or nil
local pageEditBuffer = "" -- live text while renaming a page
local addInputText = "" -- live text of the add-todo input (from onChange)
local addInputRev = 0 -- bumped to reseed (clear) the add-todo input
local newPageName = "" -- live text of the new-page input
local currentPriority = "medium"

local render

-- Per-row callbacks need distinct global names; the reconciler dispatches
-- callbacks by name only. getfenv() is the script environment lua_getglobal
-- reads from, so assigning into it defines the callback the host will find.
local env = getfenv()
local function rowCb(prefix, index, fn)
  local name = prefix .. "_" .. index
  env[name] = fn
  return name
end

local function tr(key)
  return noctalia.tr(key)
end

local function getData()
  return noctalia.state.get("todos") or { todos = {}, pages = {}, currentPageId = 0 }
end

local function priorityColor(priority)
  if noctalia.getConfig("use_custom_colors") then
    if priority == "high" then
      return noctalia.getConfig("color_high")
    elseif priority == "low" then
      return noctalia.getConfig("color_low")
    end
    return noctalia.getConfig("color_medium")
  end
  if priority == "high" then
    return "error"
  elseif priority == "low" then
    return "on_surface_variant"
  end
  return "primary"
end

-- Applies an alpha to a priority color for the row tint. Theme role tokens
-- take a "/alpha" suffix; custom hex colors need the alpha as hex digits.
local function tinted(color, alpha)
  if color:sub(1, 1) == "#" then
    return string.format("%s%02x", color, math.floor(alpha * 255 + 0.5))
  end
  return color .. "/" .. tostring(alpha)
end

-- ui.label has no strikethrough prop; overlay a combining long-stroke on
-- every character so completed todos still read as struck through.
local function strikethrough(text)
  local out = {}
  for _, code in utf8.codes(text) do
    table.insert(out, utf8.char(code))
    table.insert(out, "\u{0336}")
  end
  return table.concat(out)
end

-- Active items first (in original order), completed items after (if shown).
local function filteredTodos(todos, pageId, showCompleted)
  local active, completed = {}, {}
  for _, t in ipairs(todos) do
    if t.pageId == pageId then
      if t.completed then
        table.insert(completed, t)
      else
        table.insert(active, t)
      end
    end
  end
  if showCompleted then
    for _, t in ipairs(completed) do
      table.insert(active, t)
    end
  end
  return active
end

-- ── Todo list view ───────────────────────────────────────────────────────

local function renderTodoRow(todo, index)
  local isEditing = editingId == todo.id
  local children = {}

  -- Rectangle checkbox with rounded corners
  local checkboxChildren = {}
  if todo.completed then
    table.insert(checkboxChildren, ui.glyph({
      name = "check",
      size = 14,
      color = "on_primary",
    }))
  end
  table.insert(children, ui.box({
    width = 20,
    height = 20,
    radius = 4,
    fill = todo.completed and "#22c55e" or "surface_variant",
    border = todo.completed and nil or "outline",
    onClick = rowCb("onToggle", index, function()
      noctalia.state.set("command", { action = "toggle", id = todo.id })
    end),
  }, checkboxChildren))

  if isEditing then
    table.insert(children, ui.input({
      key = "edit-" .. todo.id,
      value = todo.text,
      flexGrow = 1,
      focus = true,
      onChange = rowCb("onEditChange", index, function(value)
        editBuffers[todo.id] = value
      end),
      onSubmit = rowCb("onEditSubmit", index, function(value)
        noctalia.state.set("command", { action = "update", id = todo.id, text = value })
        editBuffers[todo.id] = nil
        editingId = nil
        render()
      end),
    }))
    table.insert(children, ui.button({
      glyph = "check",
      variant = "primary",
      onClick = rowCb("onEditConfirm", index, function()
        local value = editBuffers[todo.id] or todo.text
        noctalia.state.set("command", { action = "update", id = todo.id, text = value })
        editBuffers[todo.id] = nil
        editingId = nil
        render()
      end),
    }))
    table.insert(children, ui.button({
      glyph = "close",
      variant = "ghost",
      onClick = rowCb("onEditCancel", index, function()
        editBuffers[todo.id] = nil
        editingId = nil
        render()
      end),
    }))
  else
    table.insert(children, ui.label({
      text = todo.completed and strikethrough(todo.text) or todo.text,
      color = todo.completed and "on_surface_variant" or "on_surface",
      flexGrow = 1,
    }))
    table.insert(children, ui.button({
      glyph = "pencil",
      variant = "ghost",
      onClick = rowCb("onEditStart", index, function()
        editingId = todo.id
        editBuffers[todo.id] = todo.text
        render()
      end),
    }))
    table.insert(children, ui.button({
      glyph = "trash",
      variant = "ghost",
      onClick = rowCb("onDelete", index, function()
        noctalia.state.set("command", { action = "delete", id = todo.id })
      end),
    }))
  end

  return ui.row({
    key = "todo-" .. todo.id,
    gap = 8,
    align = "center",
    fill = tinted(priorityColor(todo.priority), 0.08),
    radius = 4,
    padding = 4,
  }, children)
end

local function renderTabs(pages, currentPageId)
  -- Manage-pages button goes first so it stays anchored at the top-left,
  -- rather than trailing after however many page tabs currently exist.
  local tabs = {
    ui.button({
      key = "tab-manage",
      glyph = "settings",
      variant = "ghost",
      onClick = "onOpenManagePages",
    }),
  }
  for i, page in ipairs(pages) do
    table.insert(tabs, ui.button({
      key = "tab-" .. page.id,
      text = page.name,
      variant = page.id == currentPageId and "primary" or "ghost",
      onClick = rowCb("onPageSwitch", i, function()
        if page.id ~= currentPageId then
          noctalia.state.set("command", { action = "setPage", pageId = page.id })
        end
      end),
    }))
  end
  return ui.row({ gap = 4 }, tabs)
end

local function renderAddInput()
  -- Priority selector: neutral/outline by default, switches to the semantic
  -- variant only when selected.
  local function priorityBox(label, priority, variant)
    local isSelected = currentPriority == priority
    return ui.button({
      text = label,
      variant = isSelected and variant or "outline",
      onClick = rowCb("onPrioritySet", priority, function()
        currentPriority = priority
        render()
      end),
    })
  end

  return ui.column({ gap = 6 }, {
    -- Priority selector with distinct colors
    ui.row({ gap = 4, align = "center" }, {
      priorityBox("H", "high", "destructive"),
      priorityBox("M", "medium", "primary"),
      priorityBox("L", "low", "secondary"),
      -- L uses "secondary" (no green variant exists on ui.button); its exact
      -- hue follows the active theme, not guaranteed to be literal green.
    }),
    -- Text input + add button
    ui.row({ gap = 6, align = "center" }, {
      ui.input({
        key = "add-input-" .. addInputRev,
        placeholder = tr("panel.add_placeholder"),
        flexGrow = 1,
        onChange = "onAddInputChange",
        onSubmit = "onAddTodo",
      }),
      ui.button({ glyph = "plus", variant = "primary", onClick = "onAddTodo" }),
    }),
  })
end

local function todosView(data, count)
  local pages = data.pages or {}
  local currentPageId = data.currentPageId or 0
  local showCompleted = noctalia.getConfig("show_completed")

  local rows = {}
  local filtered = filteredTodos(data.todos or {}, currentPageId, showCompleted)
  for i, todo in ipairs(filtered) do
    table.insert(rows, renderTodoRow(todo, i))
  end

  local listContent
  if #rows == 0 then
    listContent = ui.column({ key = "todo-list-" .. currentPageId, flexGrow = 1, align = "center", justify = "center" }, {
      ui.label({ text = tr("panel.empty"), color = "on_surface_variant" }),
    })
  else
    -- Keyed per page so switching pages remounts the scroll view instead of
    -- reusing one whose internal scroll offset came from a different page.
    listContent = ui.scroll({ key = "todo-list-" .. currentPageId, flexGrow = 1, gap = 4 }, rows)
  end

  return ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({
        text = tr("panel.title") .. " (" .. tostring(count) .. ")",
        fontSize = 16,
        fontWeight = "bold",
        flexGrow = 1,
      }),
      ui.button({ glyph = "close", variant = "ghost", onClick = "onClosePanel" }),
    }),
    renderTabs(pages, currentPageId),
    listContent,
    renderAddInput(),
  })
end

-- ── Manage-pages view ────────────────────────────────────────────────────

local function pageRow(page, index, pageCount)
  local isDefault = page.id == 0
  local canDelete = not isDefault and pageCount > 1
  local isEditing = editingPageId == page.id
  local children = {}

  if isEditing then
    table.insert(children, ui.input({
      key = "page-edit-" .. page.id,
      value = page.name,
      flexGrow = 1,
      focus = true,
      onChange = rowCb("onPageNameChange", index, function(value)
        pageEditBuffer = value
      end),
      onSubmit = rowCb("onPageRenameSubmit", index, function(value)
        noctalia.state.set("command", { action = "renamePage", id = page.id, name = value })
        editingPageId = nil
        render()
      end),
    }))
    table.insert(children, ui.button({
      glyph = "check",
      variant = "primary",
      onClick = rowCb("onPageRenameConfirm", index, function()
        noctalia.state.set("command", { action = "renamePage", id = page.id, name = pageEditBuffer })
        editingPageId = nil
        render()
      end),
    }))
    table.insert(children, ui.button({
      glyph = "close",
      variant = "ghost",
      onClick = rowCb("onPageRenameCancel", index, function()
        editingPageId = nil
        render()
      end),
    }))
  else
    table.insert(children, ui.label({ text = page.name, flexGrow = 1 }))
    table.insert(children, ui.button({
      glyph = "pencil",
      variant = "ghost",
      onClick = rowCb("onPageEditStart", index, function()
        editingPageId = page.id
        pageEditBuffer = page.name
        render()
      end),
    }))
    table.insert(children, ui.button({
      glyph = "trash",
      variant = "ghost",
      enabled = canDelete,
      onClick = rowCb("onPageDelete", index, function()
        noctalia.state.set("command", { action = "deletePage", id = page.id })
      end),
    }))
  end

  return ui.row({ key = "page-" .. page.id, gap = 6, align = "center" }, children)
end

local function pagesView(data)
  local pages = data.pages or {}
  local rows = {}
  for i, page in ipairs(pages) do
    table.insert(rows, pageRow(page, i, #pages))
  end
  return ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.button({ glyph = "arrow-left", variant = "ghost", onClick = "onCloseManagePages" }),
      ui.label({ text = tr("panel.manage_pages"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
    }),
    ui.scroll({ flexGrow = 1, gap = 4 }, rows),
    ui.row({ gap = 6, align = "center" }, {
      ui.input({
        key = "new-page-input-" .. #pages,
        placeholder = tr("panel.new_page_placeholder"),
        flexGrow = 1,
        onChange = "onNewPageNameChange",
        onSubmit = "onAddPage",
      }),
      ui.button({ glyph = "plus", variant = "primary", onClick = "onAddPage" }),
    }),
  })
end

-- ── Render ───────────────────────────────────────────────────────────────

render = function()
  local data = getData()
  local count = noctalia.state.get("count")
  if type(count) ~= "number" then
    count = 0
  end

  if view == "pages" then
    panel.render(pagesView(data))
  else
    panel.render(todosView(data, count))
  end
end

-- ── Callbacks ────────────────────────────────────────────────────────────

function onOpen(_context)
  editingId = nil
  editBuffers = {}
  editingPageId = nil
  view = "todos"
  addInputText = ""
  currentPriority = "medium"
  render()
end

function onClose()
  editingId = nil
  editBuffers = {}
  editingPageId = nil
end

function onClosePanel()
  panel.close()
end

function onAddInputChange(value)
  addInputText = value
end

function onAddTodo(value)
  -- Try to get text from the callback value first, then from our buffer
  local text = ""
  if value ~= nil and value ~= "" then
    text = value
  elseif addInputText ~= nil and addInputText ~= "" then
    text = addInputText
  end

  text = noctalia.string.trim(text)
  if text == "" then
    return
  end

  local data = getData()
  noctalia.state.set("command", {
    action = "add",
    text = text,
    priority = currentPriority,
    pageId = data.currentPageId or 0,
  })
  addInputText = ""
  currentPriority = "medium"
  addInputRev += 1
  render()
end

function onOpenManagePages()
  view = "pages"
  editingPageId = nil
  render()
end

function onCloseManagePages()
  view = "todos"
  editingPageId = nil
  render()
end

function onNewPageNameChange(value)
  newPageName = value
end

function onAddPage(value)
  local name = value or newPageName
  noctalia.state.set("command", { action = "addPage", name = name })
  newPageName = ""
  render()
end

-- The service publishes a fresh "todos" snapshot after every mutation
-- (including ones driven by the widget or another panel instance).
noctalia.state.watch("todos", function(_value)
  render()
end)
