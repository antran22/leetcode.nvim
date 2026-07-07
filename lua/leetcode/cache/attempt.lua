local path = require("plenary.path")
local config = require("leetcode.config")
local Problemlist = require("leetcode.cache.problemlist")

local log = require("leetcode.logger")

---@type Path
local file = config.storage.cache:joinpath("attempts")

---@class lc.cache.AttemptEntry
---@field title_slug string
---@field lang string
---@field at integer

---@class lc.cache.Attempt
local Attempt = {}

---@return lc.cache.AttemptEntry[]
function Attempt.read()
    if not file:exists() then
        return {}
    end

    local contents = file:read()
    if not contents or contents == "" then
        return {}
    end

    local ok, entries = pcall(vim.json.decode, contents)
    if not ok or type(entries) ~= "table" then
        return {}
    end

    return entries
end

---@param entries lc.cache.AttemptEntry[]
function Attempt.write(entries)
    file:write(vim.json.encode(entries), "w")
end

---@param title_slug string
---@return boolean
function Attempt.has(title_slug)
    return not not vim.tbl_filter(function(e)
        return e.title_slug == title_slug
    end, Attempt.read())[1]
end

---Register a new (or refresh an existing) attempt for `title_slug`.
---@param title_slug string
---@param lang string
function Attempt.add(title_slug, lang)
    local entries = Attempt.read()

    local found = false
    for _, e in ipairs(entries) do
        if e.title_slug == title_slug then
            e.lang = lang
            e.at = os.time()
            found = true
            break
        end
    end

    if not found then
        table.insert(entries, {
            title_slug = title_slug,
            lang = lang,
            at = os.time(),
        })
    end

    Attempt.write(entries)
end

---Remove an attempt entry (e.g. once the question receives an Accepted verdict).
---@param title_slug string
function Attempt.remove(title_slug)
    local entries = Attempt.read()

    local filtered = vim.tbl_filter(function(e)
        return e.title_slug ~= title_slug
    end, entries)

    if #filtered ~= #entries then
        Attempt.write(filtered)
    end
end

---Resolve cached attempts to problem-list questions, then merge in any `notac`
---problems (submitted but not yet Accepted) that aren't already tracked locally.
---Attempts come first, sorted by recency; `notac`-only problems follow in
---frontend-id order. Stale attempt slugs no longer in the problem cache are
---skipped with a warning.
---@return lc.cache.Question[]
function Attempt.questions()
    local entries = Attempt.read()

    local by_slug = {}
    for _, q in ipairs(Problemlist.get()) do
        by_slug[q.title_slug] = q
    end

    ---@param a lc.cache.AttemptEntry
    table.sort(entries, function(a, b)
        return (a.at or 0) > (b.at or 0)
    end)

    local out, seen = {}, {}
    for _, e in ipairs(entries) do
        local q = by_slug[e.title_slug]
        if q then
            table.insert(out, q)
            seen[e.title_slug] = true
        else
            log.warn(("Attempt cache: `%s` not found in problem list, skipping"):format(e.title_slug))
        end
    end

    for _, q in ipairs(Problemlist.get()) do
        if q.status == "notac" and not seen[q.title_slug] then
            table.insert(out, q)
            seen[q.title_slug] = true
        end
    end

    return out
end

function Attempt.delete()
    if not file:exists() then
        return false
    end
    return pcall(path.rm, file)
end

return Attempt
