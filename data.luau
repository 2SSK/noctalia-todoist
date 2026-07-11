--!nonstrict
-- Todoist service -- owns todo/page data, persists to disk, publishes state.
--
-- The panel and widget are thin clients: they read the published "todos" /
-- "count" state and drive mutations by writing to the "command" channel.
-- This keeps data in memory across panel open/close cycles and lets the bar
-- widget show the active count without ever opening the panel.

local DATA_FILE = "todos.json"

local todos = {}
local pages = { { id = 0, name = "General" } }
local currentPageId = 0
local lastId = 0
local nextPageId = 0
local dirty = false

-- ── Helpers ──────────────────────────────────────────────────────────────

local function tr(key)
  return noctalia.tr(key)
end

local function dataPath()
  return noctalia.pluginDir() .. "/" .. DATA_FILE
end

-- Monotonic: guards against two todos landing in the same second.
local function nextId()
  local now = tonumber(noctalia.formatTime("%s")) or 0
  lastId = math.max(lastId, now * 1000) + 1
  return lastId
end

local function findTodo(id)
  for i, t in ipairs(todos) do
    if t.id == id then
      return t, i
    end
  end
  return nil, nil
end

local function findPage(id)
  for i, p in ipairs(pages) do
    if p.id == id then
      return p, i
    end
  end
  return nil, nil
end

local function pageNameTaken(name, excludeId)
  for _, p in ipairs(pages) do
    if p.id ~= excludeId and p.name == name then
      return true
    end
  end
  return false
end

-- ── Persistence ──────────────────────────────────────────────────────────

local function load()
  local raw = noctalia.readFile(dataPath())
  if raw == nil then
    return
  end
  local decoded = noctalia.json.decode(raw)
  if type(decoded) ~= "table" then
    noctalia.notifyError(tr("title"), tr("error_load_failed"))
    return
  end
  todos = decoded.todos or {}
  pages = decoded.pages or { { id = 0, name = "General" } }
  currentPageId = decoded.currentPageId or 0

  for _, t in ipairs(todos) do
    if type(t.id) == "number" and t.id > lastId then
      lastId = t.id
    end
  end
  for _, p in ipairs(pages) do
    if type(p.id) == "number" and p.id > nextPageId then
      nextPageId = p.id
    end
  end
end

-- Crash-safe write: temp file first, then atomic rename over the real path.
local function save()
  local data = { todos = todos, pages = pages, currentPageId = currentPageId }
  local encoded = noctalia.json.encode(data, true)
  if encoded == nil then
    return
  end
  local path = dataPath()
  local tmpPath = path .. ".tmp"
  local ok, err = noctalia.writeFile(tmpPath, encoded)
  if not ok then
    noctalia.notifyError(tr("title"), err or tr("error_save_failed"))
    return
  end
  local renamed, rerr = noctalia.renameFile(tmpPath, path)
  if not renamed then
    noctalia.notifyError(tr("title"), rerr or tr("error_save_failed"))
    return
  end
  dirty = false
end

-- ── State publication ────────────────────────────────────────────────────

local function publish()
  noctalia.state.set("todos", { todos = todos, pages = pages, currentPageId = currentPageId })
  local activeCount = 0
  for _, t in ipairs(todos) do
    if not t.completed then
      activeCount += 1
    end
  end
  noctalia.state.set("count", activeCount)
end

local function mutate()
  dirty = true
  save()
  publish()
end

-- ── Todo CRUD ────────────────────────────────────────────────────────────

local VALID_PRIORITIES = { high = true, medium = true, low = true }

local function addTodo(text, priority, pageId)
  local trimmed = noctalia.string.trim(text or "")
  if trimmed == "" then
    return
  end
  if not VALID_PRIORITIES[priority] then
    priority = "medium"
  end
  if pageId == nil or findPage(pageId) == nil then
    pageId = currentPageId
  end
  table.insert(todos, {
    id = nextId(),
    text = trimmed,
    completed = false,
    createdAt = noctalia.formatTime("%Y-%m-%dT%H:%M:%SZ"),
    pageId = pageId,
    priority = priority,
    details = "",
  })
  mutate()
end

local function toggleTodo(id)
  local t = findTodo(id)
  if t == nil then
    return
  end
  t.completed = not t.completed
  mutate()
end

local function updateTodoText(id, newText)
  local t = findTodo(id)
  if t == nil then
    return
  end
  local trimmed = noctalia.string.trim(newText or "")
  if trimmed == "" then
    return
  end
  t.text = trimmed
  mutate()
end

local function deleteTodo(id)
  local _, index = findTodo(id)
  if index == nil then
    return
  end
  table.remove(todos, index)
  mutate()
end

local function clearCompleted()
  local filtered = {}
  for _, t in ipairs(todos) do
    if not (t.completed and t.pageId == currentPageId) then
      table.insert(filtered, t)
    end
  end
  todos = filtered
  mutate()
end

local function setPage(pageId)
  if findPage(pageId) == nil then
    return
  end
  currentPageId = pageId
  mutate()
end

-- ── Page CRUD ────────────────────────────────────────────────────────────

local function addPage(name)
  local trimmed = noctalia.string.trim(name or "")
  if trimmed == "" then
    return
  end
  if pageNameTaken(trimmed, nil) then
    noctalia.notifyError(tr("title"), tr("error_duplicate_page"))
    return
  end
  nextPageId += 1
  table.insert(pages, { id = nextPageId, name = trimmed })
  mutate()
end

local function renamePage(id, name)
  local page = findPage(id)
  if page == nil then
    return
  end
  local trimmed = noctalia.string.trim(name or "")
  if trimmed == "" then
    return
  end
  if pageNameTaken(trimmed, id) then
    noctalia.notifyError(tr("title"), tr("error_duplicate_page"))
    return
  end
  page.name = trimmed
  mutate()
end

local function deletePage(id)
  if id == 0 then
    noctalia.notifyError(tr("title"), tr("error_cannot_delete_default_page"))
    return
  end
  if #pages <= 1 then
    noctalia.notifyError(tr("title"), tr("error_cannot_delete_last_page"))
    return
  end
  local _, index = findPage(id)
  if index == nil then
    return
  end
  table.remove(pages, index)
  for _, t in ipairs(todos) do
    if t.pageId == id then
      t.pageId = 0
    end
  end
  if currentPageId == id then
    currentPageId = 0
  end
  mutate()
end

-- ── Command handler ──────────────────────────────────────────────────────

local function handleCommand(cmd)
  if type(cmd) ~= "table" or type(cmd.action) ~= "string" then
    return
  end
  local a = cmd.action
  if a == "add" then
    addTodo(cmd.text, cmd.priority, cmd.pageId)
  elseif a == "toggle" then
    toggleTodo(cmd.id)
  elseif a == "update" then
    updateTodoText(cmd.id, cmd.text)
  elseif a == "delete" then
    deleteTodo(cmd.id)
  elseif a == "setPage" then
    setPage(cmd.pageId)
  elseif a == "clearCompleted" then
    clearCompleted()
  elseif a == "addPage" then
    addPage(cmd.name)
  elseif a == "renamePage" then
    renamePage(cmd.id, cmd.name)
  elseif a == "deletePage" then
    deletePage(cmd.id)
  end
end

-- ── Init ─────────────────────────────────────────────────────────────────

noctalia.setUpdateInterval(5000)
load()
publish()

-- Safety net only: every mutation above already saves synchronously.
function update()
  if dirty then
    save()
  end
end

noctalia.state.watch("command", handleCommand)
