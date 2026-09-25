-- ═══════════════════════════════════════════════════════════════════════════
-- 69書吧 (69shuba.tw) source plugin for NoveLA
-- Version 1.0.0 (2026-09-20)
--
-- NOT the same site as the existing "69shuba" plugin (www.69shuba.com —
-- Simplified, GBK, /book/{id}.htm URLs, different library): 69shuba.tw is
-- the Traditional-Chinese portal of the family — UTF-8, its own URL scheme
-- (/book/{id}/, /indexlist/{id}/, /read/{bid}/{cid}) and a DIFFERENT book
-- database (book 342441 exists here, 404s on .com). Hence a separate
-- plugin id: "69shubaTw".
--
-- ANTI-BOT — Tencent EdgeOne "aegis" captcha, NOT Cloudflare:
--   Server: Edge/1.1.28. From datacenter IPs every path answers 403 with a
--   custom human-verification page (reCAPTCHA v3 checkbox + Turnstile
--   script; the token POSTs to /aegis_captcha_verify?rule_uuid=…; verified
--   cookies __ct_ac_cpg + __ct_cya_ckt follow). The engine's stock CF
--   detector does NOT recognize it (Server ≠ cloudflare) — so this plugin
--   registers cf_options.trigger_markers. With those, the app's interceptor
--   runs its WebView bypass ladder on the challenge page: solve the
--   "I'm not a robot" checkbox once in the WebView (it auto-passes on real
--   devices), tap Done, and the retry carries the __ct_* cookies. On
--   residential IPs (typical phones) the site usually serves pages with no
--   challenge at all.
--   Path asymmetry (verified via the Google-Translate proxy): /, /book/*,
--   /read/*, /search/*, /fenlei/*, /quanben/* pass from Google's IPs while
--   /indexlist/* (the chapter catalog) is challenged even there — expect the
--   catalog to be the first surface to need the WebView solve.
--
-- COVERS: served by the open CDN p.69shuba.tw (no challenge, verified) —
--   DIRECT image URLs, no wsrv.nl proxy (deliberately, per user request —
--   and unlike wuxiabox/wtrlab/novel543/oop whose CDNs sit behind WAFs).
--   Deterministic pattern: https://p.69shuba.tw/{id÷1000}/{id}/{id}s.jpg
--   (verified on 342441/337296/338557/400577) — synthesized when the book
--   page cannot be fetched.
--
-- WHAT'S NEW IN v1.2.0 (the "indexlist has 100 chapters per page" fix):
--   • Book URLs: /book/{id}/ AND /indexlist/{id}/ AND /read/{bid}/{cid} all
--     work — the id is extracted from any shape and every fetch derives
--     from the canonical /book/{id}/ page (the user may paste the catalog
--     URL straight from the browser).
--   • Real-TOC pager: global 下一页 scan (any wrapper div), ALL select
--     elements enumerated (indexselect, -top, -bottom), option values =
--     page URLs, book-id-form option values rejected (the v1.1.0 trap:
--     "/indexlist/342441/" as page-1's option inflated totalPages to
--     342441), 【共N章】 heading cross-check (ceil(N/100) pages), window
--     chase, blind page-2 probe when no pager signal parses at all.
--   • Parallel prefetch: pages 2..N fetched in one http_get_batch.
--   • Soft-serve guard + canonical chapter URLs (trailing slashes stripped)
--     so cross-page dedupe, walk termination and loop detection all agree.
--   • tocMerge keep-rule fixed: the chase/batch-merged LAST page is no
--     longer dropped from the cache by the later page-1 merge (v1.1.0
--     wasted a re-fetch per book; with the batch it would waste N).
--
-- WHAT'S IN THE PLUGIN:
--   • Browse: 全部小說 ranking /quanben/fenlei/{N}/ (1-based) with a
--     9-option picker: 完結全部 + 8 categories → /fenlei/{slug}/{N}/
--     (玄幻 xuanhuan 仙俠 wuxia 都市 dushi 歷史 lishi 遊戲 youxi
--      科幻 kehu 言情 yanqing 同人 tongren). 30 books/page.
--   • Search: GET /search/?searchkey={q}&searchtype=all (page 1) and
--     /search/{N}?searchkey={q} (page N — both live-verified); the same
--     table.list-item cards as the listings, with .highlight spans inside
--     titles (text concatenation merges them). hasNext from the pager's
--     下一页 link.
--   • Book pages /book/{id}/: title td.info h1, cover img, author /
--     category / 狀態+字數 / 更新 timestamp / latest chapter
--     (p#lastchapter-row), description div.intro p.
--   • Chapter catalog /indexlist/{id}/ — WAF-hard from datacenter IPs but
--     served to reader devices (user-verified: 100 chapters per page). The
--     v1.2.0 pager engine handles every family markup variant observed on
--     the sibling wcshuba.com (same CMS generation, /chapterlist/{id}…):
--     h3 "章節目錄【共N章】", select#indexselect (or #indexselect-top/-bottom
--     — ALL selects are enumerated) whose option VALUES are the page URLs
--     (/indexlist/{id}/{N}/), 下一页 links anywhere in the page, 100
--     chapters per page, the main list duplicated (same-URL anchors — cid
--     dedupe). Pages 2..N are prefetched in ONE parallel http_get_batch
--     (used by the shipped xbiquge/novelfull/hitomi plugins), so a full
--     5-page/450-chapter TOC costs ~2 network rounds. Soft-serve loop
--     guard: a wrong page-N URL that re-serves page 1 is detected (first
--     chapter comparison) and never pollutes the TOC.
--   • Chapter text /read/{bid}/{cid}: div#nr1 <p> paragraphs ONLY (ad
--     divs — .reader-ad with loadAdv() — are interleaved BETWEEN the <p>s
--     inside the content div; p-only selection skips them all). Titles
--     carry a "(cur / total)" sub-page suffix — when total > 1 the plugin
--     fetches /read/{bid}/{cid}/{n} sub-pages and concatenates them.
--     Domain-watermark lines (69shuba.tw etc.) and (本章完) are stripped.
--   • Translator mode (the novel543 engine, source zh-TW): Google free
--     dict endpoint + MyMemory + gtx fallbacks, translation cache,
--     circuit breaker, pass-through on any error. Non-Chinese search
--     queries are translated to Traditional Chinese first (zh-TW variant,
--     zh-CN retry when the first finds nothing — user titles may be either).
--   • Chrome Mobile UA preset (mobile-first site).
--
-- Site facts (live-verified 2026-09-20 via the Google-Translate proxy —
-- direct datacenter access is EdgeOne-challenged on every path):
--   • Encoding:       UTF-8 (NOT GBK like 69shuba.com). Content mostly
--                     Traditional; nav/pager literals Simplified
--                     (上一页 下一页 第N页) — both are matched.
--   • Listings:       /quanben/fenlei/{N}/ (titled 全部小說小說排行榜,
--                     nav link 完結), /fenlei/{slug}/{N}/ (排行榜).
--   • Cards:          table.list-item → td img (cover), div.article a
--                     (title; .highlight spans in search), p.fs12.gray
--                     span.mr15 ("作者:X[　N萬字]"), synopsis in a
--                     span.fs12.gray.
--   • Pager:          div.index-container → span.disabled-btn (prev on
--                     p1) + select#indexselect (option value = page path,
--                     10-option window) + a.index-container-btn (下一页 =
--                     next). hasNext = a 下一页 link exists.
--   • Book page:      div.bookinfo table → td img + td.info (h1 title,
--                     作者：/類別：/狀態：…/更新：/最新： p#lastchapter-row),
--                     table.book-op (章節目錄 → /indexlist/{id}/,
--                     #startread → ch1), div.intro p, ul.last9 (latest).
--   • TOC:            /indexlist/{id}/ (+ /{N}/ pages — the site-wide
--                     pager shape, CONFIRMED by the wcshuba.com sibling
--                     (same CMS generation): /chapterlist/{id}/{N}.html,
--                     100 chapters per page, select options carry every
--                     page URL, 下一页 link until the last page).
--   • Sibling proof:   wcshuba.com = the same new-CMS family, NOT WAF'd —
--                     its /chapterlist/{id} pages were captured live and
--                     drove the v1.2.0 pager engine (see research/wc_*.html).
--   • Chapter page:   h1#nr_title "第N章 …(cur / total)", div#nr1 <p>,
--                     #pb_prev/#pb_mulu/#pb_next (上一章/目錄/下一章),
--                     #startread ch1 = /read/342441/890315.
--   • Covers:         //p.69shuba.tw/{id÷1000}/{id}/{id}s.jpg — open CDN.
--   • Author pages:   /author/{urlencoded name}/ (not used by the plugin).
--   • No JSON API:    classic PHP/Jieqi-style rendering (addbookcase,
--                     bookcase, recentread are cookie features — skipped).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
local VERSION = "1.2.0"
id       = "69shubaTw"
name     = "69書吧 (69shuba.tw)"
version  = "1.2.0"
baseUrl  = "https://69shuba.tw/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/69shuba.png"

-- Anti-bot: the site's EdgeOne "aegis" captcha is invisible to the engine's
-- stock Cloudflare detector (Server: Edge). These markers make the engine's
-- interceptor run its WebView bypass ladder whenever the challenge page is
-- served (any status code) — solve the checkbox once, cookies carry over.
cf_options = {
  trigger_markers = {
    "aegis_captcha_verify",              -- the challenge's POST endpoint
    "recaptcha-v3-container",            -- the checkbox widget markup
    "Please complete human verification" -- the challenge page <title>
  }
}

-- ── Constants ────────────────────────────────────────────────────────────────
local SITE = "https://69shuba.tw"

-- Settings preference keys
local PREF_MODE   = "s69tw_mode"      -- raw | translate
local PREF_TLANG  = "s69tw_tlang"     -- target language code, default "en"
local PREF_TR_CH  = "s69tw_tr_chapters" -- "1" | "0" (translate chapter titles)

-- ── Site taxonomy (live-verified 2026-09-20) ────────────────────────────────
-- value = the /fenlei/ slug. "quanben" = the all/completed ranking surface.
local CATEGORIES = {
  { value = "xuanhuan", en = "Fantasy (玄幻)",    zh = "玄幻" },
  { value = "wuxia",    en = "Immortal (仙俠)",   zh = "仙俠" },
  { value = "dushi",    en = "Urban (都市)",      zh = "都市" },
  { value = "lishi",    en = "History (歷史)",    zh = "歷史" },
  { value = "youxi",    en = "Games (遊戲)",      zh = "遊戲" },
  { value = "kehu",     en = "Sci-Fi (科幻)",     zh = "科幻" },
  { value = "yanqing",  en = "Romance (言情)",    zh = "言情" },
  { value = "tongren",  en = "Fanfic (同人)",     zh = "同人" }
}

-- Static English lookups for fixed site vocabulary (English target only).
local STATIC_EN = {
  ["玄幻"] = "Fantasy",   ["仙俠"] = "Immortal Heroes",
  ["都市"] = "Urban",     ["歷史"] = "History",
  ["历史"] = "History",   ["遊戲"] = "Games",
  ["游戏"] = "Games",     ["科幻"] = "Sci-Fi",
  ["言情"] = "Romance",   ["同人"] = "Fanfic",
  ["連載"] = "Ongoing",   ["连载"] = "Ongoing",
  ["完結"] = "Completed", ["完结"] = "Completed",
  ["完本"] = "Completed"
}

-- ── Generic helpers ──────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function hasCJK(s)
  return type(s) == "string" and string.find(s, "[\228-\233]") ~= nil
end

-- Book id from ANY book-URL shape the user may paste or the engine may
-- store: /book/{id}/ (canonical), /indexlist/{id}/ (the catalog — the
-- browser's 章節目錄 target; users paste it straight from the address bar)
-- or /read/{bid}/{cid} (a chapter link).
local function bookIdFromUrl(bookUrl)
  local u = bookUrl or ""
  local n = tonumber(string.match(u, "/book/(%d+)"))
  if n then return n end
  n = tonumber(string.match(u, "/indexlist/(%d+)"))
  if n then return n end
  return tonumber(string.match(u, "/read/(%d+)/%d+"))
end

-- The canonical book-page URL for details fetches — whatever URL shape the
-- book was added with, metadata comes from /book/{id}/ (the only page with
-- title/cover/description; /indexlist/ holds the catalog, /read/ a chapter).
local function canonicalBookUrl(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if id then return SITE .. "/book/" .. id .. "/" end
  return bookUrl
end

-- ── Covers — DIRECT from the open CDN p.69shuba.tw ──────────────────────────
-- No wsrv.nl proxy on this site (the CDN is not WAF-protected). The URL is
-- also synthesizable from the book id alone:
--   https://p.69shuba.tw/{floor(id/1000)}/{id}/{id}s.jpg
local function synthCover(bookId)
  if not bookId then return nil end
  local folder = math.floor(bookId / 1000)
  return string.format("https://p.69shuba.tw/%d/%d/%ds.jpg", folder, bookId, bookId)
end

local function coverFromImg(img, bookId)
  local u = absUrl(img)
  if u ~= "" then return u end
  return synthCover(bookId)
end

-- ── Clock (NoveLA's os_time returns MILLISECONDS) ───────────────────────────
local function nowMs()
  local ok, v = pcall(os_time)
  if ok and type(v) == "number" and v > 0 then
    if v < 100000000000 then v = v * 1000 end
    return v
  end
  return nil
end

-- ── HTTP ─────────────────────────────────────────────────────────────────────
-- UTF-8 site, pages served directly (200). EdgeOne challenges surface as
-- {success=false} AFTER the engine's interceptor runs its WebView ladder
-- (trigger_markers above) — the plugin just makes normal requests and
-- handles failures with show_error.

local function httpGetPage(pathOrUrl)
  local url = pathOrUrl
  if not string_starts_with(url, "http") then url = SITE .. url end
  return http_get(url, {
    headers = {
      ["Referer"] = SITE .. "/",
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    }
  })
end

-- ── Short-lived page cache ───────────────────────────────────────────────────
-- Opening a book fires getBookTitle / Cover / Description / Genres / Status /
-- LastUpdate / ChapterListHash separately — the cache collapses them into
-- one fetch. 60s TTL, 12 pages. Chapter text NEVER cached.
local pageCache, pageCacheOrder = {}, {}
local PAGE_TTL_MS    = 60000
local PAGE_CACHE_MAX = 12

local function pageCachePut(path, r)
  local now = nowMs()
  if not now then return end
  if pageCache[path] == nil then
    pageCacheOrder[#pageCacheOrder + 1] = path
    if #pageCacheOrder > PAGE_CACHE_MAX then
      pageCache[table.remove(pageCacheOrder, 1)] = nil
    end
  end
  pageCache[path] = { r = r, t = now }
end

local function pageCacheFresh(path)
  local now = nowMs()
  local e = pageCache[path]
  if e and now and (now - e.t) < PAGE_TTL_MS then return e.r end
  return nil
end

local function fetchPageCached(bookUrl)
  local path = string.match(bookUrl, "^https?://[^/]+(/.*)$") or bookUrl
  local hit = pageCacheFresh(path)
  if hit then return hit end
  local r = httpGetPage(path)
  if r and r.success then pageCachePut(path, r) end
  return r
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Translator core (copied from novel543.lua — battle-tested through 197
-- harness checks on novel543 and the oop/bixiange deployments).
-- Source language: zh-TW (69shuba.tw indexes Traditional Chinese; some
-- synopses are Simplified — Google's dict endpoint handles both from a
-- zh-TW source tag).
-- ═══════════════════════════════════════════════════════════════════════════
-- Engine: Google's free dict endpoint (client=dict-chrome-ex) — POST with
-- repeated q params returns one translation per q. With sl=auto the shape
-- nests the detected source: [["t1","zh-CN"]] — both shapes are parsed.
-- No API key, no OAuth. Request chain, each step only on failure:
--   1. POST translate.googleapis.com/translate_a/t
--   2. POST clients5.google.com/translate_a/t
--   3. GET  translate.googleapis.com/translate_a/t (q in the URL)
--   4. GET  clients5.google.com/translate_a/t
--   5. MyMemory (api.mymemory.translated.net, anonymous)
--   6. Google gtx single — per item, first 6 of a failed chunk
-- EVERY failure path returns the original text, and every public entry point
-- is pcall-armored — browsing must never break because of the translator.

local TR_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
local TR_HOSTS = {
  "https://translate.googleapis.com",
  "https://clients5.google.com"
}
local TR_FAIL_LIMIT     = 3       -- consecutive failed batches before pass-through
local TR_RETRY_AFTER_MS = 600000  -- breaker half-opens after 10 minutes

local trCache      = {}       -- original → translated (session-lifetime)
local trCacheCount = 0
local trFailStreak = 0
local trDisabledAt = 0
local trProbeCount = 0        -- breaker tick when no clock is available

local function getMode()
  local ok, v = pcall(get_preference, PREF_MODE)
  if ok and v == "translate" then return "translate" end
  return "raw"
end

local function getTl()
  local ok, v = pcall(get_preference, PREF_TLANG)
  if ok and type(v) == "string" and v ~= "" then return v end
  return "en"
end

local function trChaptersEnabled()
  local ok, v = pcall(get_preference, PREF_TR_CH)
  if ok and v == "0" then return false end
  return true -- default on
end

-- Filter label builder:
--   raw mode       → "English (中文)"
--   translate mode → "English"
local function flLabel(en, zh)
  if getMode() == "translate" then return en end
  if zh and zh ~= "" and hasCJK(zh) then return en .. " (" .. zh .. ")" end
  return en
end

local function trActive()
  if getMode() ~= "translate" then return false end
  if trFailStreak < TR_FAIL_LIMIT then return true end
  local now = nowMs()
  if now then
    return (now - trDisabledAt) >= TR_RETRY_AFTER_MS -- half-open after 10 min
  end
  return (trProbeCount % 16) == 0 -- no clock: probe once every 16 batches
end

local function trCachePut(k, v)
  if trCacheCount > 4000 then return end -- hard cap
  if trCache[k] == nil then trCacheCount = trCacheCount + 1 end
  trCache[k] = v
end

-- Parse the /t endpoint response. Accepted shapes (Lua 1-based):
--   {"t1","t2"}                 (explicit sl)
--   {{"t1","src"},{"t2","src"}} (sl=auto)
-- Returns an array of exactly `want` strings, or nil when malformed.
local function parseTrArray(j, want)
  if type(j) ~= "table" then return nil end
  local out = {}
  for i = 1, want do
    local e = j[i]
    local t = nil
    if type(e) == "string" then
      t = e
    elseif type(e) == "table" then
      if type(e[1]) == "string" then t = e[1]
      elseif type(e[1]) == "table" and type(e[1][1]) == "string" then t = e[1][1] end
    end
    if t == nil then return nil end
    out[i] = t
  end
  return out
end

-- GET variant with q params in the URL, split to keep URLs under ~1400 chars.
local function trGetChunk(host, texts, sl, tl)
  local out = {}
  local i = 1
  while i <= #texts do
    local group, encLen = {}, 0
    while i <= #texts do
      local enc = "q=" .. url_encode(texts[i])
      if encLen + #enc + 1 > 1400 and #group > 0 then break end
      group[#group + 1] = texts[i]
      encLen = encLen + #enc + 1
      i = i + 1
    end
    local qs = {}
    for _, t in ipairs(group) do qs[#qs + 1] = "q=" .. url_encode(t) end
    local url = host .. "/translate_a/t?client=dict-chrome-ex&sl=" .. sl
      .. "&tl=" .. url_encode(tl) .. "&" .. table.concat(qs, "&")
    local r = http_get(url, { headers = { ["User-Agent"] = TR_UA } })
    if not (r and r.success and type(r.body) == "string"
            and string.sub(r.body, 1, 1) == "[") then return nil end
    local res = parseTrArray(json_parse(r.body), #group)
    if not res then return nil end
    for k = 1, #group do
      local v = res[k]
      if v == nil or v == "" then v = group[k] end
      out[#out + 1] = v
    end
  end
  return out
end

-- Steps 1-4: Google dict endpoint, POST then GET, on both hosts.
local function trRequestGoogle(texts, sl, tl)
  local qs = {}
  for _, t in ipairs(texts) do qs[#qs + 1] = "q=" .. url_encode(t) end
  local qstr = table.concat(qs, "&")
  for _, host in ipairs(TR_HOSTS) do
    local url = host .. "/translate_a/t?client=dict-chrome-ex&sl=" .. sl .. "&tl=" .. url_encode(tl)
    local r = http_post(url, qstr, {
      headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["User-Agent"]   = TR_UA
      }
    })
    if r and r.success and type(r.body) == "string"
       and string.sub(r.body, 1, 1) == "[" then
      local res = parseTrArray(json_parse(r.body), #texts)
      if res then return res end
    end
    local res = trGetChunk(host, texts, sl, tl)
    if res then return res end
  end
  return nil
end

-- Step 6: classic gtx single endpoint — one text per request.
local function trGtxSingle(text, tl)
  local url = "https://translate.googleapis.com/translate_a/single"
    .. "?client=gtx&sl=auto&tl=" .. url_encode(tl)
    .. "&dt=t&q=" .. url_encode(text)
  local r = http_get(url, { headers = { ["User-Agent"] = TR_UA } })
  if r and r.success and type(r.body) == "string"
     and string.sub(r.body, 1, 1) == "[" then
    local j = json_parse(r.body)
    if type(j) == "table" and type(j[1]) == "table" and type(j[1][1]) == "table"
       and type(j[1][1][1]) == "string" then
      return j[1][1][1]
    end
  end
  return nil
end

-- MyMemory fallback — per-item GET, short texts only.
local function trChunkMyMemory(texts, tl)
  local out = {}
  local any = false
  for i, t in ipairs(texts) do
    out[i] = t
    if #t <= 300 then
      local url = "https://api.mymemory.translated.net/get?q=" .. url_encode(t)
                   .. "&langpair=zh|" .. url_encode(tl)
      local r = http_get(url, { headers = { ["User-Agent"] = TR_UA } })
      if r and r.success and type(r.body) == "string"
         and string.sub(r.body, 1, 1) == "{" then
        local j = json_parse(r.body)
        if type(j) == "table" and type(j.responseData) == "table"
           and type(j.responseData.translatedText) == "string" then
          local tr = j.responseData.translatedText
          if tr ~= "" and tr ~= t and string.find(tr, "MYMEMORY WARNING") == nil then
            out[i] = tr
            any = true
          end
        end
      end
    end
  end
  if not any then return nil end
  return out
end

-- Translate an array of strings; ALWAYS returns an array of the same length.
local function translateBatchImpl(texts)
  local n = #texts
  if n == 0 then return texts end
  if not trActive() then
    trProbeCount = trProbeCount + 1
    return texts
  end

  -- cache pass
  local out, pending, pIdx = {}, {}, {}
  for i = 1, n do
    local c = trCache[texts[i]]
    if c ~= nil then out[i] = c
    else pending[#pending + 1] = texts[i]; pIdx[#pIdx + 1] = i end
  end
  if #pending == 0 then return out end

  -- chunked requests: ≤40 items and ≤3000 chars per chunk
  local CHUNK_MAX = 40
  local s = 1
  while s <= #pending do
    local chunk, chars = {}, 0
    while s + #chunk <= #pending and #chunk < CHUNK_MAX do
      local t = pending[s + #chunk]
      if chars + #t > 3000 and #chunk > 0 then break end
      chunk[#chunk + 1] = t
      chars = chars + #t
    end
    local base = s
    s = s + #chunk

    local tl = getTl()
    local res = trRequestGoogle(chunk, "zh-TW", tl)
    local usedFallback = false
    if not res then
      res = trChunkMyMemory(chunk, tl)
      usedFallback = true
    end
    if res and #res == #chunk then
      if not usedFallback then trFailStreak = 0 end
      for k = 1, #chunk do
        local v = res[k]
        if v == nil or v == "" then v = chunk[k] end
        out[pIdx[base + k - 1]] = v
        trCachePut(chunk[k], v)
      end
    else
      local anyOk = false
      local cap = #chunk
      if cap > 6 then cap = 6 end
      for k = 1, cap do
        local v = nil
        if #chunk[k] <= 400 then v = trGtxSingle(chunk[k], tl) end
        if v and v ~= "" then
          out[pIdx[base + k - 1]] = v
          trCachePut(chunk[k], v)
          anyOk = true
        else
          out[pIdx[base + k - 1]] = chunk[k]
        end
      end
      for k = cap + 1, #chunk do
        out[pIdx[base + k - 1]] = chunk[k]
      end
      if not anyOk then
        trFailStreak = trFailStreak + 1
        if trFailStreak >= TR_FAIL_LIMIT then
          trDisabledAt = nowMs() or 0
          log_info("69shubaTw: translator disabled for 10 min (3 failed batches)")
        end
      end
    end
  end
  return out
end

local function translateBatch(texts)
  if type(texts) ~= "table" then return texts end
  local ok, res = pcall(translateBatchImpl, texts)
  if ok and type(res) == "table" and #res == #texts then return res end
  if not ok then log_info("69shubaTw: translator error: " .. tostring(res)) end
  return texts
end

-- Translate a single string (cached; original on failure).
local function translateOne(text)
  if type(text) ~= "string" or text == "" or not trActive() then return text end
  local c = trCache[text]
  if c ~= nil then return c end
  local r = translateBatch({ text })
  return r[1] or text
end

-- Fixed site vocabulary: free for English, API (cached) for other languages.
local function translateVocab(text)
  if type(text) ~= "string" or text == "" then return text end
  if not trActive() then return text end
  if getTl() == "en" and STATIC_EN[text] then return STATIC_EN[text] end
  return translateOne(text)
end

-- Reverse direction for search: user-language query → Chinese. The site
-- indexes Traditional titles, so zh-TW is the primary variant; the zh-CN
-- variant is retried by the caller when the first finds nothing (user
-- titles on this site may be either script).
local function translateQueryToZh(query, tlZh)
  if not trActive() then return nil end
  local ok, res = pcall(trRequestGoogle, { query }, "auto", tlZh)
  if ok and type(res) == "table" and res[1] and res[1] ~= query then return res[1] end
  return nil
end


-- ═══════════════════════════════════════════════════════════════════════════
-- List-page parsing + catalog browse
-- ═══════════════════════════════════════════════════════════════════════════
-- /quanben/fenlei/, /fenlei/{slug}/ and /search/ share the card markup:
--   table.list-item
--     td a img                     → cover (//p.69shuba.tw/…)
--     td div.article a (1st)       → title + book URL (search pages wrap
--                                    match terms in .highlight spans —
--                                    text concatenation merges them)
--     p.fs12.gray span.mr15        → "作者:X" or "作者:X　N萬字"
--     a span.fs12.gray             → synopsis snippet
-- Pager (div.index-container): prev is a disabled SPAN on page 1 (an <a> on
-- later pages), next is ALWAYS an <a> whose text is 下一页 — hasNext =
-- such a link exists. The select#indexselect options carry page paths.

local function parseListCards(body)
  local items = {}
  if not body then return items end
  for _, card in ipairs(html_select(body, "table.list-item")) do
    local img = html_attr(card.html, "img", "src")
    local titleEl = html_select_first(card.html, "div.article a")
    local href = titleEl and titleEl.href or ""
    if titleEl and href and href ~= "" then
      local title = string_clean(titleEl.text or "")
      if title ~= "" then
        local bid = tonumber(string.match(absUrl(href), "/book/(%d+)"))
        items[#items + 1] = {
          title = title,
          url   = absUrl(href),
          cover = coverFromImg(img, bid)
        }
      end
    end
  end
  return items
end

-- hasNext: an <a> in the pager whose text is 下一页 (Simplified — the
-- site's pager literals are Simplified even on Traditional pages).
local function listHasNext(body)
  if not body then return false end
  for _, a in ipairs(html_select(body, "div.index-container a")) do
    local t = a.text or ""
    if string.find(t, "下一页") or string.find(t, "下一頁") then
      local href = a.href or ""
      if string.find(href, "javascript") == nil then return true end
    end
  end
  return false
end

local function translateCatalogItems(items)
  if not trActive() or #items == 0 then return items end
  local titles = {}
  for i = 1, #items do titles[i] = items[i].title end
  local tr = translateBatch(titles)
  for i = 1, #items do items[i].title = tr[i] end
  return items
end

local function unreachableError(what)
  if type(show_error) == "function" then
    show_error("69shuba.tw unreachable",
      "Could not load " .. what .. " from 69shuba.tw (network issue or the " ..
      "site's human-verification wall).\n\nIf a verification page appears, " ..
      "tick the \"I'm not a robot\" box once — it usually passes on real " ..
      "devices — then retry.")
  end
end

-- ── Catalog ──────────────────────────────────────────────────────────────────
-- Default surface: the 全部小說 ranking /quanben/fenlei/{N}/ (1-based in
-- the URL; the app's index is 0-based). Filtered: /fenlei/{slug}/{N}/.

function getCatalogList(index)
  local path = "/quanben/fenlei/"
  if index > 0 then path = "/quanben/fenlei/" .. tostring(index + 1) .. "/" end
  local r = httpGetPage(path)
  if not (r and r.success) then
    unreachableError("the novel list")
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getCatalogFiltered(index, filters)
  local cat = filters and filters.category
  local path
  if cat and cat ~= "" and cat ~= "all" then
    if cat == "quanben" then
      path = "/quanben/fenlei/" .. tostring(index + 1) .. "/"
    else
      path = "/fenlei/" .. cat .. "/" .. tostring(index + 1) .. "/"
    end
  else
    path = "/quanben/fenlei/"
    if index > 0 then path = "/quanben/fenlei/" .. tostring(index + 1) .. "/" end
  end
  local r = httpGetPage(path)
  if not (r and r.success) then
    unreachableError("the category")
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getFilterList()
  local catOptions = {
    { value = "all",     label = flLabel("All Novels (全部小說)", "全部小說") },
    { value = "quanben", label = flLabel("Completed Ranking (完結)", "完結") }
  }
  for _, c in ipairs(CATEGORIES) do
    catOptions[#catOptions + 1] = { value = c.value, label = flLabel(c.en, c.zh) }
  end
  return {
    {
      type = "select",
      key = "category",
      label = "Category (分類)",
      options = catOptions
    }
  }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Search — GET /search/?searchkey={q}&searchtype=all (page 1, live-verified)
-- and /search/{N}?searchkey={q} (page N, from the pager's own URLs).
-- ═══════════════════════════════════════════════════════════════════════════
-- In Translator mode a non-Chinese query is first translated to Traditional
-- Chinese (the site indexes zh-TW titles); when that finds nothing the
-- Simplified variant is tried once — titles on this site may be either.

function getCatalogSearch(index, query)
  if type(query) ~= "string" or query == "" then
    return { items = {}, hasNext = false }
  end

  local q = query
  if not hasCJK(q) then
    local tw = translateQueryToZh(q, "zh-TW")
    if tw then q = tw end
  end

  local function searchUrl(index, keyword)
    if index <= 0 then
      return SITE .. "/search/?searchkey=" .. url_encode(keyword) .. "&searchtype=all"
    end
    -- app index is 0-based; the site's page-N URL is 1-based (/search/2?…)
    return SITE .. "/search/" .. tostring(index + 1) .. "?searchkey=" .. url_encode(keyword)
  end

  local r = http_get(searchUrl(index, q), {
    headers = {
      ["Referer"] = SITE .. "/",
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    }
  })
  if not (r and r.success) then
    unreachableError("the search")
    return { items = {}, hasNext = false }
  end

  local items = parseListCards(r.body)

  -- zh-CN retry (translated queries that matched nothing, first page only)
  if index == 0 and q ~= query and #items == 0 then
    local cn = translateQueryToZh(query, "zh-CN")
    if cn and cn ~= q then
      local r2 = http_get(searchUrl(0, cn), {
        headers = { ["Referer"] = SITE .. "/", ["Accept"] = "text/html,*/*;q=0.8" }
      })
      if r2 and r2.success then
        items = parseListCards(r2.body)
        r = r2
      end
    end
  end

  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter catalog — three-layer strategy (v1.1.0)
-- ═══════════════════════════════════════════════════════════════════════════
-- Layer 1 (real): /indexlist/{id}/{N}/ pages — the true TOC. That path is
--   EdgeOne-challenged even from Google's IPs (a path-specific WAF rule;
--   re-verified 2026-09-20: /book/342441/ 200-real vs /indexlist/342441/
--   403-captcha one minute apart). On reader devices it usually passes, and
--   cf_options.trigger_markers route the challenge into the app's WebView
--   ladder when it doesn't (one checkbox solve → cookies carry over).
-- Layer 2 (seed): the book page itself carries 最新章節預覽 (ul.last9 — up to
--   12 latest chapters with real titles) and #startread (chapter 1's URL).
--   The /book/ path is NOT WAF-hard, so a readable TOC exists even on app
--   builds without the WebView ladder.
-- Layer 3 (walk): /read/ pages are NOT WAF-hard either. When /indexlist/ is
--   unreachable the TOC is built by following the chapters' own #pb_next
--   chain from chapter 1 in WALK_CHUNK-sized virtual pages — no captcha
--   needed, works on ANY app build. Virtual page 1 IS the first walk chunk
--   (so positions come out in reading order), and the seed chapters are
--   emitted as the FINAL virtual page once the walk reaches them. Progress
--   persists across calls and app restarts; the walk aborts at the first
--   failed fetch (the oop.tw solver-storm lesson) and resumes where it
--   stopped. When the book grows past the seed window between refreshes,
--   the walk resumes from the last known chapter's #pb_next (one fetch).
-- The v1.0.0 bug this fixes: parsePage returned nil when /indexlist/ was
--   blocked → builds that don't propagate show_error surfaced the bare
--   "parsePage returned non-table" error. parsePage(1) now NEVER returns
--   nil — worst case an empty table after show_error.

local SEED_TOTAL_PAGES = 9999  -- forces a full reparse once the real TOC loads
local WALK_CHUNK       = 40    -- chapters per virtual page while walking
local SEED_TTL_MS      = 10000 -- replay memo: the engine calls parsePage(1) twice

local function cidFromUrl(u)
  return tonumber(string.match(u or "", "/read/%d+/(%d+)"))
end

-- Canonical chapter URL: strips queries/fragments/trailing slashes,
-- requires the same-book /read/{bookId}/{cid} path shape, returns a
-- SITE-absolute URL or nil. CANONICAL FORM = SITE.."/read/{bid}/{cid}"
-- (no trailing slash) — parseTocChapters, the seed and the walk all
-- produce it, so URL-set membership (walk termination, soft-serve
-- detection, cross-page dedupe) is always string-exact.
local function normalizeReadUrl(u, bookId)
  if type(u) ~= "string" then return nil end
  local idStr = tostring(bookId)
  -- path only (strip query/fragment), then strip trailing slashes
  local path = string.match(u, "^https?://[^/]+(/[^?#]*)")
    or string.match(u, "^(/[^?#]*)")
  if not path then return nil end
  path = string.gsub(path, "/+$", "")
  -- the path must be EXACTLY /read/{bid}/{cid} (rejects sub-page
  -- /read/{bid}/{cid}/{n} shapes and foreign-book links)
  local cidStr = string.match(path, "^/read/" .. idStr .. "/(%d+)$")
  if not cidStr then return nil end
  return SITE .. "/read/" .. idStr .. "/" .. cidStr
end

-- Collect chapters from an /indexlist/ page. Returns an array of
-- { cid = n, title = s, url = s } sorted by cid. Layout-agnostic: the only
-- stable shape is the /read/{bookId}/{cid} href itself. URLs are built in
-- the CANONICAL form (trailing slashes/extensions stripped) so pages,
-- seeds and walk chunks compare equal; same-cid anchors (the site renders
-- the chapter list twice — verified on the wcshuba sibling) dedupe out.
local function parseTocChapters(body, bookId)
  local seen, out = {}, {}
  if not body or not bookId then return out end
  local pat = "/read/" .. tostring(bookId) .. "/(%d+)"
  for _, a in ipairs(html_select(body, "a")) do
    local href = a.href or ""
    local cidStr = string.match(href, pat)
    if cidStr then
      local cid = tonumber(cidStr)
      if cid and not seen[cid] then
        local title = string_clean(a.text or "")
        if title == "" then title = string_clean(a.title or "") end
        if title ~= "" then
          seen[cid] = true
          out[#out + 1] = { cid = cid, title = title,
                            url = SITE .. "/read/" .. tostring(bookId) .. "/" .. cidStr }
        end
      end
    end
  end
  table.sort(out, function(x, y) return x.cid < y.cid end)
  return out
end

-- ── Pager intel (v1.2.0) ───────────────────────────────────────────────────
-- The family pager (wcshuba sibling, live-verified) offers THREE signals:
--   1. select option VALUES = the page URLs themselves
--      ("/indexlist/{id}/2/"; the .tw list surfaces use the same
--      component). The id may be indexselect, indexselect-top,
--      indexselect-bottom (top/bottom pagers) — ALL selects enumerated.
--   2. a 下一页 anchor (next page), ANYWHERE (wrapper class varies:
--      div.index-container on .tw lists, div.listpage on wcshuba).
--   3. an h3 "章節目錄【共N章】" heading (total chapter count).
-- Returns (maxPage, optionCount, pageUrls) — pageUrls[n] = absolute URL.
-- REJECTS values whose "page number" is the BOOK ID (page-1's option may
-- be the unnumbered "/indexlist/{id}/" form — the v1.1.0 trap that
-- inflated totalPages to 342441) and absurd counts (> 2000 pages).
local function tocPagerInfo(body, bookId)
  local maxp, count = 1, 0
  local pageUrls = {}
  if not body then return maxp, count, pageUrls end
  local idStr = tostring(bookId or "")
  local sels = html_select(body, "select[id*=indexselect]")
  if #sels == 0 then sels = html_select(body, "select") end
  local seenVal = {}
  for _, sel in ipairs(sels) do
    for _, opt in ipairs(html_select(sel.html, "option")) do
      local ok, v = pcall(function() return opt.attr("value") end)
      if ok and type(v) == "string" and v ~= "" and not seenVal[v] then
        seenVal[v] = true
        -- primary: the path segment after /indexlist/{id}
        local n = tonumber(string.match(v, "/indexlist/" .. idStr .. "/(%d+)"))
          or tonumber(string.match(v, "/indexlist/" .. idStr .. "[_%-](%d+)"))
        -- generic fallbacks: query shape, bare number, trailing path number
        -- (slash or .html — the wcshuba family paginates /{N}.html)
        if not n then
          n = tonumber(string.match(v, "/(%d+)%?"))
            or tonumber(string.match(v, "^(%d+)$"))
            or tonumber(string.match(v, "/(%d+)/?$"))
            or tonumber(string.match(v, "/(%d+)%.h?t?m?l?$"))
        end
        if n and n ~= bookId and n > 0 and n <= 2000 then
          count = count + 1
          if n > maxp then maxp = n end
          -- only SAME-PATH (indexlist) option values are fetchable page
          -- URLs on this site; foreign-path values (a sibling CMS shape)
          -- still contribute their page number
          if pageUrls[n] == nil and string.find(v, "/indexlist/", 1, true) then
            pageUrls[n] = absUrl(v)
          end
        end
      end
    end
  end
  return maxp, count, pageUrls
end

-- The pager's 下一页 link href (nil when absent / javascript) — GLOBAL
-- scan: the wrapper class varies between the .tw list pages
-- (div.index-container) and the family catalog pages (div.listpage), so
-- every anchor on the page is examined (plain-text find, both scripts).
local function tocNextLink(body)
  if not body then return nil end
  for _, a in ipairs(html_select(body, "a")) do
    local t = a.text or ""
    if string.find(t, "下一页", 1, true) or string.find(t, "下一頁", 1, true) then
      local href = a.href or ""
      if href ~= "" and string.find(href, "javascript", 1, true) == nil then
        return href
      end
    end
  end
  return nil
end

-- The page-N URL template, learned from the pager's 下一页 link:
--   "/indexlist/342441/2/" → base "/indexlist/342441" → page N = base.."/N/"
-- Tolerates an .html-suffixed next link (the wcshuba family shape
-- "/chapterlist/{id}/2.html") by stripping it — page URLs are then tried
-- BOTH with and without .html by the fetcher.
local function tocPageBase(body)
  local href = tocNextLink(body)
  if href then
    local base = string.match(href, "^(.*)/%d+%.?h?t?m?l?/?$")
      or string.match(href, "^(.*)/%d+/?$")
    if base and string.find(base, "/indexlist/", 1, true) then return base end
  end
  return nil
end

-- Total chapters from the catalog heading (h3 "章節目錄【共N章】" on the
-- wcshuba sibling) → expected page count at the site's 100/page. Only a
-- HINT: wrong guesses cost at most a couple of probe fetches (the chase
-- verifies with real pages), so the bare 共N章 form is accepted too.
local TOC_PAGE_SIZE = 100
local function tocExpectedPages(body)
  local n = tonumber(string.match(body or "", "【共(%d+)章】"))
    or tonumber(string.match(body or "", "共(%d+)章"))
  if n and n > 0 and n <= 30000 then
    local pages = math.ceil(n / TOC_PAGE_SIZE)
    if pages < 1 then pages = 1 end
    return pages, n
  end
  return nil, nil
end

-- ── Seed (layer 2) ──────────────────────────────────────────────────────────
-- ul.last9 anchors → latest chapters (real titles); #startread → ch1's URL
-- (its anchor text is 立即閱讀, NOT a title — chapter 1 is discovered with
-- its real title by the walk, which starts exactly at #startread).
-- seedMemo[bookUrl] = { seed = {list, startUrl}, page1 = <returned list>, ts }
local seedMemo = {}
local seedFetchFailed = {} -- [bookUrl] = true: /book/ fetch failed this process

local function seedFromBookPage(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil end
  -- the BOOK page carries the seed — canonical /book/{id}/ regardless of
  -- the URL shape the book was added with (/indexlist/, /read/…)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then
    seedFetchFailed[bookUrl] = true
    return nil
  end
  local readPat = "/read/" .. tostring(bookId) .. "/(%d+)"
  local byCid = {}
  for _, a in ipairs(html_select(r.body, "ul.last9 a")) do
    local cid = tonumber(string.match(a.href or "", readPat))
    if cid then
      local title = string_clean(a.text or "")
      if title ~= "" and title ~= "更多章節>>" and title ~= "更多章节>>" then
        byCid[cid] = title
      end
    end
  end
  local startUrl = nil
  local sr = html_select_first(r.body, "#startread")
  if sr then
    startUrl = normalizeReadUrl(absUrl(sr.href or ""), bookId)
  end
  local cids = {}
  for c in pairs(byCid) do cids[#cids + 1] = c end
  if #cids == 0 and not startUrl then return nil end
  table.sort(cids)
  local list = {}
  for _, c in ipairs(cids) do
    list[#list + 1] = { title = byCid[c], url = SITE .. "/read/" .. bookId .. "/" .. c }
  end
  return { list = list, startUrl = startUrl }
end

local function seedFromMemo(bookUrl)
  local m = seedMemo[bookUrl]
  if not m then return nil end
  local now = nowMs()
  if now and (now - m.ts) < SEED_TTL_MS then return m end
  seedMemo[bookUrl] = nil
  return nil
end

-- The walk's termination set: URLs the seed already covers. A fresh seed
-- first (an ongoing book's last9 moved forward); the cached seed page as a
-- fallback when the book page is unreachable (tried once per process).
local function tocSeedUrls(bookUrl, entry)
  local m = seedFromMemo(bookUrl)
  local set = {}
  if m and m.seed then
    for _, ch in ipairs(m.seed.list) do set[ch.url] = true end
    return set
  end
  if not seedFetchFailed[bookUrl] then
    local s = seedFromBookPage(bookUrl)
    if s then
      for _, ch in ipairs(s.list) do set[ch.url] = true end
      return set
    end
  end
  if entry and entry.pages and entry.pages[1] then
    for _, ch in ipairs(entry.pages[1]) do set[ch.url] = true end
  end
  return set
end

-- ── Persistent TOC cache (set_preference) ───────────────────────────────────
-- One preference per book: "s69tw_toc_<id>" =
--   v1: "1|<totalPages>|<urlBase>|<data>"
--   v2: "2|<totalPages>|<urlBase>|<r|w>|<walkNext>|<seedPage>|<data>"
-- data = <page>\031<title>\031<url>\030… \029… ( \029 page sep, \030 chapter
-- sep, \031 field sep )
-- mode "r" (real): /indexlist/ pagination. Interior pages (page < totalPages)
--   are immutable (the site only APPENDS chapters) and served with zero
--   network; the last known page and beyond are always fetched fresh.
-- mode "w" (walk): virtual #pb_next-chain pages. pages[1] is the seed
--   (bookkeeping + termination set + stale-serve fallback); pages[2..N] are
--   walk chunks (virtual page N-1); when the walk reaches the seed, the seed
--   chapters are emitted as the FINAL walk page (index seedPage) so chapter
--   positions come out in reading order. walkNext is the frontier URL (the
--   next chapter to fetch; nil = walk complete). A mode switch in either
--   direction DROPS the other mode's pages: walk pagination and site
--   pagination do not align, keeping both would corrupt the TOC.

local TOC_PREF_PREFIX = "s69tw_toc_"
local TOC_PREF_LRU    = "s69tw_toc_lru"
local TOC_MAX_BOOKS   = 5      -- LRU cap (cached books)
local TOC_MAX_BYTES   = 150000 -- per-book serialization cap

local function tocPrefKey(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  return id and (TOC_PREF_PREFIX .. id) or nil
end

local function tocCacheLoad(bookUrl)
  local key = tocPrefKey(bookUrl)
  if not key then return nil end
  local ok, v = pcall(get_preference, key)
  if not (ok and type(v) == "string" and v ~= "") then return nil end
  local mode
  local tpStr, base, modeCh, walkNext, seedPage, data =
    string.match(v, "^2|(%d+)|([^|]*)|([rw])|([^|]*)|([^|]*)|(.*)$")
  if tpStr then
    mode = (modeCh == "w") and "walk" or "real"
  else
    local ver
    ver, tpStr, base, data = string.match(v, "^(%d+)|(%d+)|([^|]*)|(.*)$")
    if not ver then return nil end
    mode, walkNext, seedPage = "real", nil, nil
  end
  local entry = {
    totalPages = tonumber(tpStr) or 1,
    urlBase    = base or "",
    mode       = mode,
    walkNext   = (walkNext ~= nil and walkNext ~= "") and walkNext or nil,
    seedPage   = tonumber(seedPage) or nil,
    pages      = {}
  }
  for block in string.gmatch(data, "[^\029]+") do
    local pStr, recs = string.match(block, "^(%d+)\031(.*)$")
    local p = tonumber(pStr)
    if p then
      local chs = {}
      for rec in string.gmatch(recs, "[^\030]+") do
        local t, u = string.match(rec, "^(.*)\031(.*)$")
        if t and u and t ~= "" and u ~= "" then
          chs[#chs + 1] = { title = t, url = u }
        end
      end
      entry.pages[p] = chs
    end
  end
  return entry
end

-- Merge one parsed page into the entry. A mode switch drops the other
-- mode's pages. Real mode keeps every cached page at or below the NEW page
-- count (v1.2.0: the v1.1.0 "-1" dropped the chase/batch-prefetched LAST
-- page whenever page 1 merged afterwards — a wasted re-fetch per book);
-- the last page is simply never SERVED from cache (tocFetchPageN re-fetches
-- it fresh — it may have grown), so keeping it is harmless.
-- Walk mode keeps everything (walk pages are append-only).
local function tocMerge(entry, page, totalPages, chapters, urlBase, mode, walkNext)
  mode = mode or "real"
  local old = entry or { totalPages = totalPages, urlBase = urlBase or "",
                         pages = {}, mode = mode, walkNext = nil, seedPage = nil }
  local pages = {}
  if old.mode == mode then
    if mode == "real" then
      local keep = math.min(old.totalPages or 1, totalPages)
      for p, chs in pairs(old.pages or {}) do
        if p <= keep then pages[p] = chs end
      end
    else
      for p, chs in pairs(old.pages or {}) do pages[p] = chs end
    end
  end
  pages[page] = chapters
  return {
    totalPages = totalPages,
    urlBase    = urlBase or old.urlBase or "",
    mode       = mode,
    walkNext   = (mode == "walk") and (walkNext or old.walkNext) or nil,
    seedPage   = (mode == "walk") and old.seedPage or nil,
    pages      = pages
  }
end

local function tocCacheSave(bookUrl, entry)
  local key = tocPrefKey(bookUrl)
  if not key then return end
  local pnums = {}
  for p in pairs(entry.pages or {}) do pnums[#pnums + 1] = p end
  table.sort(pnums)
  local blocks = {}
  for _, p in ipairs(pnums) do
    local recs = {}
    for _, ch in ipairs(entry.pages[p]) do
      recs[#recs + 1] = ch.title .. "\031" .. ch.url
    end
    blocks[#blocks + 1] = tostring(p) .. "\031" .. table.concat(recs, "\030")
  end
  local data = table.concat(blocks, "\029")
  if #data > TOC_MAX_BYTES then return end -- oversized: skip persisting
  local modeCh = (entry.mode == "walk") and "w" or "r"
  local ok = pcall(set_preference, key,
    "2|" .. tostring(entry.totalPages or 1) .. "|" .. (entry.urlBase or "") ..
    "|" .. modeCh .. "|" .. (entry.walkNext or "") .. "|" ..
    tostring(entry.seedPage or "") .. "|" .. data)
  if not ok then return end
  -- LRU bookkeeping: evict least-recently-used books beyond the cap
  local id = string.sub(key, #TOC_PREF_PREFIX + 1)
  local okL, lru = pcall(get_preference, TOC_PREF_LRU)
  local order = {}
  if okL and type(lru) == "string" and lru ~= "" then
    for v in string.gmatch(lru, "[^,]+") do order[#order + 1] = v end
  end
  local keep = { id }
  for _, v in ipairs(order) do
    if v ~= id and #keep < TOC_MAX_BOOKS then keep[#keep + 1] = v end
  end
  for _, v in ipairs(order) do
    local kept = false
    for _, k in ipairs(keep) do
      if k == v then kept = true; break end
    end
    if not kept then pcall(set_preference, TOC_PREF_PREFIX .. v, "") end
  end
  pcall(set_preference, TOC_PREF_LRU, table.concat(keep, ","))
end

-- Union two chapter lists by URL, cid-sorted (monotonic — no losses).
local function unionByCid(a, b)
  local seen, out = {}, {}
  for _, list in ipairs({ a, b }) do
    for _, ch in ipairs(list or {}) do
      if not seen[ch.url] then
        seen[ch.url] = true
        out[#out + 1] = ch
      end
    end
  end
  table.sort(out, function(x, y)
    return (cidFromUrl(x.url) or 0) < (cidFromUrl(y.url) or 0)
  end)
  return out
end

-- ── Parallel prefetch: pages 2..N in ONE http_get_batch ─────────────────────
-- The select's option VALUES are the page URLs — fetch them concurrently
-- (the engine's batch helper is used by the shipped xbiquge/novelfull/
-- hitomi plugins). Every fetched page is folded into the page cache (60s)
-- AND the persistent TOC cache, so the engine's page walk serves 2..N-1
-- with zero network. Tolerates partial failure: a missing page is simply
-- not cached — tocFetchPageN fetches it individually later. Skips URLs
-- already fresh in the page cache (the engine's double parsePage(1)
-- replays without any network). Bounded at 8 pages per call.
local function batchPrefetch(bookUrl, bookId, entry, base, pageUrls, upTo, page1FirstUrl)
  if type(http_get_batch) ~= "function" then return entry end
  if not upTo or upTo < 2 then return entry end
  local urls, pages = {}, {}
  for p = 2, upTo do
    if #urls >= 8 then break end
    local u = pageUrls[p]
    if not u and base and base ~= "" then u = base .. "/" .. p .. "/" end
    if u then
      u = absUrl(u)
      local path = string.match(u, "^https?://[^/]+(/.*)$") or u
      if not pageCacheFresh(path) then
        urls[#urls + 1] = u
        pages[#pages + 1] = p
      end
    end
  end
  if #urls == 0 then return entry end
  local ok, res = pcall(http_get_batch, urls, {})
  if not (ok and type(res) == "table") then return entry end
  for i = 1, #pages do
    local r = res[i]
    if type(r) == "table" and r.success and type(r.body) == "string"
       and r.body ~= "" then
      local chs = parseTocChapters(r.body, bookId)
      -- soft-serve guard: a re-served page 1 must not masquerade as page N
      -- (page 1 is not in the entry yet — compare against its first chapter)
      local dupP1 = page1FirstUrl ~= nil and #chs > 0
        and chs[1].url == page1FirstUrl
      if #chs > 0 and not dupP1 then
        local ptp = tocPagerInfo(r.body, bookId)
        local path = string.match(urls[i], "^https?://[^/]+(/.*)$") or urls[i]
        pageCachePut(path, r)
        entry = tocMerge(entry, pages[i], math.max(ptp, pages[i]), chs,
                         base, "real", nil)
      end
    end
  end
  return entry
end

-- ── Window-chase v2: the true page count ────────────────────────────────────
-- The select may be a 10-page WINDOW (every list surface of the site uses
-- one), page 1's own signals may be ambiguous, and the 【共N章】 heading
-- hints the expected count — chase resolves the truth with REAL pages:
--   • probe the max-option page (its own window reveals more; a probed
--     page without a 下一页 link IS the last page),
--   • jump straight to the heading-hinted page when higher than known,
--   • blind-probe page 2 once when NO pager signal parsed at all.
-- Every probe is a real TOC page the engine's walk needs anyway — merged
-- into the cache and served free later. Stops at the first failure or at
-- a soft-served page (wrong page-N URL re-serving page 1). Returns (tp, entry).
local function chaseTotalPages(bookUrl, bookId, tp, optionCount, hasNext, entry, base, expected, page1FirstUrl)
  local probes = 0
  while probes < 14 do
    local mustProbe =
      (hasNext and (optionCount >= 10 or optionCount == 0 or probes > 0))
      or (expected ~= nil and expected > tp)
      or (tp <= 1 and optionCount == 0 and probes == 0) -- no signal at all
    if not mustProbe then break end
    local P = math.max(tp, 2)
    if expected and expected > P then P = expected end
    local prefix = (base ~= "" and base or SITE .. "/indexlist/" .. tostring(bookId))
    -- the site's slash form first; the wcshuba-family .html form as fallback
    local pr = fetchPageCached(prefix .. "/" .. P .. "/")
    if not (pr and pr.success) then
      local pr2 = fetchPageCached(prefix .. "/" .. P .. ".html")
      if pr2 and pr2.success then pr = pr2 end
    end
    if not (pr and pr.success) then break end
    local pch = parseTocChapters(pr.body, bookId)
    if #pch == 0 then break end -- soft block / error page
    -- soft-serve guard: the probed page re-serving page 1 means the
    -- template is wrong or P is past the end — stop, keep what we know
    -- (page 1 is not in the entry yet — compare against its first chapter)
    if P > 1 and page1FirstUrl ~= nil and pch[1].url == page1FirstUrl then
      break
    end
    local ptp, pOptCount = tocPagerInfo(pr.body, bookId)
    local pNext = tocNextLink(pr.body) ~= nil
    local pExp = tocExpectedPages(pr.body)
    entry = tocMerge(entry, P, math.max(ptp, P), pch, base, "real", nil)
    probes = probes + 1
    if P > tp then tp = P end
    if ptp > tp then tp = ptp end
    if pNext then
      if pExp and pExp > tp then tp = pExp end
      if tp <= P then tp = P + 1 end -- a next link exists → at least P+1
      optionCount = pOptCount
      expected = pExp
      hasNext = true
    else
      -- no next on the probed page → P is the last page, unless the
      -- heading on THAT page says the book is longer
      if pExp and pExp > tp then
        expected = pExp
        hasNext = true
        optionCount = 0
      else
        return tp, entry
      end
    end
  end
  return tp, entry
end

-- ── Layer 3: the #pb_next walk (virtual pages) ──────────────────────────────
-- Virtual page N lives at entry.pages[N+1]. Fetch chapters sequentially
-- following each page's 下一章 link, starting from the seed's #startread
-- URL. Stops at the first failure (resumable), at the seed's chapters
-- (they are emitted as the FINAL page so positions stay in reading order),
-- at a foreign-book URL, or at the end of the book.
-- Returns the chapter list for the virtual page, or nil (stop/abort).
local function walkEnsure(bookUrl, vpage, entry, seedUrls)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId or vpage < 1 or not entry or entry.mode ~= "walk" then
    return nil
  end
  local pages = entry.pages or {}
  local idx = vpage + 1

  -- a cached walk page is complete when superseded, final, or full
  if pages[idx] and #pages[idx] > 0 and
     (pages[idx + 1] ~= nil or entry.walkNext == nil or #pages[idx] >= WALK_CHUNK) then
    return pages[idx]
  end

  -- sequential guard: only the frontier page (or the next one) can be built
  local maxP = 1
  for p in pairs(pages) do
    if p >= 2 and pages[p] and #pages[p] > 0 and p > maxP then maxP = p end
  end
  if idx < maxP or idx > maxP + 1 then return nil end

  local cur = pages[idx] or {}
  local frontier = normalizeReadUrl(entry.walkNext, bookId)
  local failed = false
  while #cur < WALK_CHUNK and frontier do
    if seedUrls[frontier] then break end                           -- seed reached
    local r = httpGetPage(frontier)
    if not (r and r.success) then failed = true break end          -- abort (resumable)
    local titleEl = html_select_first(r.body, "#nr_title")
    local title = titleEl and string_clean(titleEl.text or "") or ""
    if title ~= "" then
      title = string.gsub(title, "%s*%(.-%s*/%s*%d+%)%s*$", "")
      cur[#cur + 1] = { title = title, url = frontier }
    end
    local nextA = html_select_first(r.body, "a#pb_next")
    frontier = (nextA and nextA.href and nextA.href ~= "")
      and normalizeReadUrl(absUrl(nextA.href), bookId) or nil
  end

  if failed then
    -- save the partial chunk for resume, report the failure
    if #cur > 0 then
      tocCacheSave(bookUrl, tocMerge(entry, idx, SEED_TOTAL_PAGES, cur, "", "walk", frontier))
    end
    return nil
  end

  if #cur == 0 then
    -- walk done for this page: seed reached, end of book, or never started
    local neverStarted = (entry.walkNext == nil) and maxP <= 1
    local seedReached = frontier ~= nil
    if entry.seedPage == nil and pages[1] and #pages[1] > 0 and (seedReached or neverStarted) then
      local seedPage = pages[1]
      local pages2 = {}
      for p, chs in pairs(pages) do pages2[p] = chs end
      pages2[idx] = seedPage
      tocCacheSave(bookUrl, { totalPages = SEED_TOTAL_PAGES, urlBase = "",
        mode = "walk", walkNext = nil, seedPage = idx, pages = pages2 })
      return seedPage
    end
    return nil
  end

  tocCacheSave(bookUrl, tocMerge(entry, idx, SEED_TOTAL_PAGES, cur, "", "walk", frontier))
  return cur
end

-- ── Layers 1+2: page 1 ──────────────────────────────────────────────────────
-- Returns (chapters, totalPages, urlBase, mode) or (nil, nil, nil, nil).
-- Order: replay memo (identical result for the engine's immediate second
-- call — no second /indexlist/ ladder run) → real /indexlist/ fetch →
-- stale real cache → seed + first walk chunk → stale walk cache.
local function tocFetchPage1(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil, nil, nil, nil end

  local m = seedFromMemo(bookUrl)
  if m and m.page1 and #m.page1 > 0 then
    return m.page1, SEED_TOTAL_PAGES, "", "walk"
  end

  -- REAL: /indexlist/{id}/ (60s page cache — the double call is free).
  -- 100 chapters per page (user-verified); the full page count comes from
  -- the select options + 下一页 link + 【共N章】 heading, pages 2..N are
  -- prefetched in ONE parallel batch, and any remaining uncertainty is
  -- resolved by the chase.
  local r = fetchPageCached(SITE .. "/indexlist/" .. bookId .. "/")
  if r and r.success then
    local chapters = parseTocChapters(r.body, bookId)
    if #chapters > 0 then
      local entry = tocCacheLoad(bookUrl)
      local tp, optionCount, pageUrls = tocPagerInfo(r.body, bookId)
      local hasNext = tocNextLink(r.body) ~= nil
      local expected = tocExpectedPages(r.body)
      local base = tocPageBase(r.body) or (entry and entry.urlBase) or ""
      if base == "" then base = "/indexlist/" .. bookId end
      -- parallel prefetch of the listed pages (2..tp, ≤8) BEFORE the
      -- chase — with a clean select this loads the whole TOC here
      local batchTo = tp
      if expected and expected > batchTo then batchTo = expected end
      if batchTo > 1 then
        entry = batchPrefetch(bookUrl, bookId, entry, base, pageUrls, batchTo,
                              chapters[1] and chapters[1].url or nil)
      end
      tp, entry = chaseTotalPages(bookUrl, bookId, tp, optionCount, hasNext,
                                  entry, base, expected,
                                  chapters[1] and chapters[1].url or nil)
      if tp < 1 then tp = 1 end
      tocCacheSave(bookUrl, tocMerge(entry, 1, tp, chapters, base, "real", nil))
      return chapters, tp, base, "real"
    end
    -- 200 but no chapter anchors: soft block / JS-rendered page → fall through
  end

  -- stale REAL cache: a complete TOC from a previous session beats the seed
  local entry = tocCacheLoad(bookUrl)
  if entry and entry.mode == "real" and entry.pages[1] and #entry.pages[1] > 0 then
    return entry.pages[1], entry.totalPages, entry.urlBase, "real"
  end

  -- SEED + WALK
  local s = seedFromBookPage(bookUrl)
  if s and #s.list > 0 then
    local seedUrls = {}
    for _, ch in ipairs(s.list) do seedUrls[ch.url] = true end
    local e
    if entry and entry.mode == "walk" then
      e = entry
      local freshMin = cidFromUrl(s.list[1].url)
      local oldPage = e.seedPage and e.pages[e.seedPage] or nil
      local oldMax = oldPage and #oldPage > 0 and cidFromUrl(oldPage[#oldPage].url) or nil
      -- book grew past the seed window: resume from the last known chapter
      if e.walkNext == nil and e.seedPage and freshMin and oldMax and freshMin > oldMax then
        local r2 = httpGetPage(oldPage[#oldPage].url)
        if r2 and r2.success then
          local nextA = html_select_first(r2.body, "a#pb_next")
          local nx = (nextA and nextA.href and nextA.href ~= "")
            and normalizeReadUrl(absUrl(nextA.href), bookId) or nil
          if nx and not seedUrls[nx] then
            e.walkNext = nx
            e.seedPage = nil -- the fresh seed will be emitted at a NEW page
          end
        end
      end
      e.pages[1] = s.list
      if e.walkNext == nil and e.seedPage then
        -- walk complete: refresh the seed page (union — monotonic growth)
        e.pages[e.seedPage] = unionByCid(e.pages[e.seedPage], s.list)
      end
    else
      e = { totalPages = SEED_TOTAL_PAGES, urlBase = "", mode = "walk",
            walkNext = s.startUrl, seedPage = nil, pages = { [1] = s.list } }
    end
    tocCacheSave(bookUrl, e)
    local chunk1 = walkEnsure(bookUrl, 1, e, seedUrls)
    local page1 = (chunk1 and #chunk1 > 0) and chunk1 or s.list
    local now = nowMs()
    if now then
      seedMemo[bookUrl] = { seed = s, page1 = page1, ts = now }
    end
    return page1, SEED_TOTAL_PAGES, "", "walk"
  end

  -- stale WALK cache (book page unreachable but walk pages exist)
  if entry and entry.mode == "walk" then
    if entry.pages[2] and #entry.pages[2] > 0 then
      return entry.pages[2], SEED_TOTAL_PAGES, "", "walk"
    end
    if entry.pages[1] and #entry.pages[1] > 0 then
      return entry.pages[1], SEED_TOTAL_PAGES, "", "walk"
    end
  end

  return nil, nil, nil, nil
end

-- ── page N > 1 dispatcher ────────────────────────────────────────────────────
-- Real mode: interior pages from cache, fresh fetch otherwise, stale copy as
-- a last resort. Walk mode: virtual walk pages. No page-1 data at all: nil
-- with ZERO network (a walk without a starting point would only re-run the
-- /indexlist/ ladder — the solver-storm defense).
local function tocFetchPageN(bookUrl, page)
  if page < 2 then return nil, nil, nil, nil end
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil, nil, nil, nil end
  local entry = tocCacheLoad(bookUrl)

  if entry and entry.mode == "real" then
    -- interior page below the cached watermark: serve without network
    if page < entry.totalPages and entry.pages[page] then
      return entry.pages[page], entry.totalPages, entry.urlBase, "real"
    end
    local body = nil
    -- learned template first — the SLASH form is the site's own (learned
    -- from the next link); the .html form is the wcshuba-family fallback,
    -- tried only after the slash form fails
    local base = entry.urlBase and entry.urlBase ~= "" and entry.urlBase or nil
    local slash = "/indexlist/" .. bookId .. "/" .. tostring(page) .. "/"
    local dotHtml = "/indexlist/" .. bookId .. "/" .. tostring(page) .. ".html"
    local tries = {}
    if base then
      local u = base .. "/" .. tostring(page) .. "/"
      if u ~= slash then tries[#tries + 1] = u end
    end
    tries[#tries + 1] = slash
    if base then
      local uh = base .. "/" .. tostring(page) .. ".html"
      if uh ~= dotHtml then tries[#tries + 1] = uh end
    end
    tries[#tries + 1] = dotHtml
    for _, u in ipairs(tries) do
      local r = fetchPageCached(u)
      if r and r.success and #parseTocChapters(r.body, bookId) > 0 then
        -- soft-serve guard: a wrong URL that re-serves PAGE 1 must not
        -- masquerade as page N (a real page N never starts at chapter 1)
        local pch = parseTocChapters(r.body, bookId)
        local dupP1 = entry.pages[1] and #entry.pages[1] > 0
          and entry.pages[1][1].url == pch[1].url
        if not dupP1 then
          body = r.body
          break
        end
      end
    end
    if body then
      local chapters = parseTocChapters(body, bookId)
      local tp = tocPagerInfo(body, bookId)
      if tp < page then tp = page end
      local newBase = tocPageBase(body) or entry.urlBase or ""
      tocCacheSave(bookUrl, tocMerge(entry, page, tp, chapters, newBase, "real", nil))
      return chapters, tp, newBase, "real"
    end
    if entry.pages[page] then
      return entry.pages[page], entry.totalPages, entry.urlBase, "real" -- stale beats nothing
    end
    return nil, nil, nil, nil
  end

  if entry and entry.mode == "walk" then
    local seedUrls = tocSeedUrls(bookUrl, entry)
    return walkEnsure(bookUrl, page, entry, seedUrls)
  end

  -- no page-1 data of any kind: unanswerable without network noise
  return nil, nil, nil, nil
end

-- Chapter-title translation on COPIES (the cache stores raw titles) — a
-- fresh list is returned whenever translating is active.
local function finalizeToc(chapters)
  if trActive() and trChaptersEnabled() and #chapters > 0 then
    local titles = {}
    for i = 1, #chapters do titles[i] = chapters[i].title end
    local tr = translateBatch(titles)
    local out = {}
    for i = 1, #chapters do out[i] = { title = tr[i], url = chapters[i].url } end
    return out
  end
  return chapters
end

local function tocShowUnreachable()
  if type(show_error) == "function" then
    show_error("Chapter list unreachable",
      "The chapter list could not be loaded from 69shuba.tw (the site's " ..
      "human-verification wall or a network issue).\n\nIf a verification " ..
      "page appears, tick the \"I'm not a robot\" box once — it usually " ..
      "passes on real devices — then retry. Progress is remembered: each " ..
      "retry resumes where the last one stopped.")
  end
end
-- ═══════════════════════════════════════════════════════════════════════════
-- Book details — /book/{id}/
-- ═══════════════════════════════════════════════════════════════════════════
--   div.bookinfo table: td img (cover) + td.info:
--     h1                      title
--     p "作者：<a>作者</a>"
--     p "類別：<a>分類</a>"
--     p "狀態：連載 / 字數：66 萬字"
--     p "更新：2026-05-12 14:49:47"
--     p#lastchapter-row "最新：<a>第N章 …</a>"
--   div.intro p               description
--   #startread                first-chapter link (fallback for nothing here)

-- Label helper: value after "label：" (full-width) or "label:" (half-width).
local function afterLabel(t, label)
  local v = string.match(t, label .. "：(.*)$")
  if v == nil then v = string.match(t, label .. ":(.*)$") end
  return v
end

local function parseBookInfo(body)
  local out = {}
  for _, p in ipairs(html_select(body, "td.info p")) do
    local t = string_clean(p.text or "")
    if t ~= "" then
      if out.author == nil then
        local v = afterLabel(t, "作者")
        if v and v ~= "" then out.author = v end
      end
      if out.category == nil then
        local v = afterLabel(t, "類別")
        if v == nil then v = afterLabel(t, "类别") end
        if v and v ~= "" then out.category = v end
      end
      if out.status == nil then
        local v = afterLabel(t, "狀態")
        if v == nil then v = afterLabel(t, "状态") end
        if v then
          local st = string.match(v, "^(.-)%s*/%s*")
          if st == nil or st == "" then st = v end
          out.status = st
          local words = string.match(v, "字數：(%S+)")
          if words == nil then words = string.match(v, "字数：(%S+)") end
          if words then out.words = words end
        end
      end
      if out.updated == nil then
        local v = afterLabel(t, "更新")
        if v then
          out.updated = string.match(v, "(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d)")
            or string.match(v, "(%d%d%d%d%-%d%d%-%d%d)")
            or v
        end
      end
      if out.latest == nil then
        local v = afterLabel(t, "最新")
        if v and v ~= "" then out.latest = v end
      end
    end
  end
  return out
end

function getBookTitle(bookUrl)
  -- /book/{id}/ carries the title whatever shape the book was added with
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, "td.info h1")
  if not el then el = html_select_first(r.body, "div.bookinfo h1") end
  if not el then return nil end
  local title = string_clean(el.text)
  if title == "" then return nil end
  if trActive() then
    local tr = translateOne(title)
    if tr ~= title then return tr .. " (" .. title .. ")" end
  end
  return title
end

function getBookCoverImageUrl(bookUrl)
  -- the cover is deterministic from the book id — synthesize first so it
  -- works even when the book page is unreachable, then refine from the page
  local bookId = bookIdFromUrl(bookUrl)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if r and r.success then
    local src = html_attr(r.body, "div.bookinfo img", "src")
    local u = coverFromImg(src, bookId)
    if u then return u end
  end
  return synthCover(bookId)
end

function getBookDescription(bookUrl)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, "div.intro")
  local desc = el and string_clean(el.text) or ""
  local info = parseBookInfo(r.body)
  local header = ""
  if info.author and info.author ~= "" then
    header = header .. "作者：" .. info.author .. "\n"
  end
  if info.category and info.category ~= "" then
    header = header .. "分類：" .. info.category .. "\n"
  end
  if info.words then
    header = header .. "字數：" .. info.words .. "字\n"
  end
  if header ~= "" then header = header .. "\n" end
  if desc == "" and header == "" then return nil end
  desc = header .. desc
  if #desc > 4000 then desc = string.sub(desc, 1, 4000) end
  if trActive() then desc = translateOne(desc) end
  return desc
end

function getBookGenres(bookUrl)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then return {} end
  local info = parseBookInfo(r.body)
  local out = {}
  if info.category and info.category ~= "" then
    out[#out + 1] = translateVocab(info.category)
  end
  return out
end

function getBookStatus(bookUrl)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then return nil end
  local info = parseBookInfo(r.body)
  if info.status and info.status ~= "" then
    return translateVocab(info.status)
  end
  return nil
end

function getBookLastUpdate(bookUrl)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then return nil end
  local info = parseBookInfo(r.body)
  if info.updated then
    local d = string.match(info.updated, "(%d%d%d%d%-%d%d%-%d%d)")
    if d then return d end
  end
  return nil
end

function getChapterListHash(bookUrl)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then return nil end
  local info = parseBookInfo(r.body)
  if info.updated or info.latest then
    return tostring(info.updated or "") .. "|" .. tostring(info.latest or "")
  end
  return nil
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list — engine entry points
-- ═══════════════════════════════════════════════════════════════════════════
-- parsePage(bookUrl, page) — the engine's paginated API. Page 1 NEVER
--   returns nil (the v1.0.0 bug: engines without show_error propagation
--   surfaced the bare "parsePage returned non-table" error): worst case it
--   returns an empty table after show_error. Pages > 1 return nil on
--   failure — the engine stops the walk and keeps what it has; progress
--   persists and resumes.
-- getChapterList(bookUrl) — fallback for engines without parsePage. Same
--   three-layer core; drives the walk to completion in one call (bounded);
--   the final list is cid-sorted (cid == reading order, live-verified).

function parsePage(bookUrl, page)
  if page == 1 then
    local raw, tp = tocFetchPage1(bookUrl)
    if raw == nil or #raw == 0 then
      -- everything unreachable: guided error on builds that propagate
      -- show_error; an EMPTY TABLE (never nil!) everywhere else
      tocShowUnreachable()
      return { chapters = {}, totalPages = 1 }
    end
    return { chapters = finalizeToc(raw), totalPages = tp or 1 }
  end

  local raw, tp = tocFetchPageN(bookUrl, page)
  if raw == nil or #raw == 0 then return nil end -- engine stops the walk
  return { chapters = finalizeToc(raw), totalPages = tp or page }
end

function getChapterList(bookUrl)
  local p1, tp, _, mode = tocFetchPage1(bookUrl)
  if p1 == nil or #p1 == 0 then
    -- last resort: everything cached (any mode) with no site access
    local entry = tocCacheLoad(bookUrl)
    if entry then
      local all = {}
      local pnums = {}
      for p in pairs(entry.pages or {}) do pnums[#pnums + 1] = p end
      table.sort(pnums)
      for _, p in ipairs(pnums) do
        for _, ch in ipairs(entry.pages[p]) do all[#all + 1] = ch end
      end
      if #all > 0 then return finalizeToc(all) end
    end
    tocShowUnreachable()
    return {}
  end

  local chapters, seenUrl = {}, {}
  for _, ch in ipairs(p1) do
    chapters[#chapters + 1] = ch
    seenUrl[ch.url] = true
  end

  if mode == "walk" then
    -- legacy engines: drive the virtual walk to completion (bounded; each
    -- page aborts at the first failed fetch and resumes on the next call)
    local entry = tocCacheLoad(bookUrl)
    local seedUrls = tocSeedUrls(bookUrl, entry)
    for vpage = 2, 60 do -- ≤ 60 × 40 = 2400 chapters per call
      local raw = walkEnsure(bookUrl, vpage, entry, seedUrls)
      if raw == nil then break end
      entry = tocCacheLoad(bookUrl) -- pick up the saved frontier
      local added = 0
      for _, ch in ipairs(raw) do
        if not seenUrl[ch.url] then
          chapters[#chapters + 1] = ch
          seenUrl[ch.url] = true
          added = added + 1
        end
      end
      if added == 0 then break end
    end
  else
    -- real mode: walk the site's pages, ABORT at the first failure (when
    -- the EdgeOne challenge does not clear, each failed fetch already cost
    -- a full WebView-solver ladder — walking on would launch it per page)
    tp = tp or 1
    for p = 2, tp do
      local raw, tp2 = tocFetchPageN(bookUrl, p)
      if raw == nil then break end -- ABORT at the first failed page
      if tp2 and tp2 > tp then tp = tp2 end
      for _, ch in ipairs(raw) do
        -- cross-page dedupe: a wrong page-N URL that soft-serves page 1
        -- again must not duplicate chapters
        if not seenUrl[ch.url] then
          chapters[#chapters + 1] = ch
          seenUrl[ch.url] = true
        end
      end
    end
  end

  -- cid == reading order (live-verified): the final sort fixes any seed /
  -- walk interleaving and the site's swapped-adjacent quirks
  table.sort(chapters, function(x, y)
    return (cidFromUrl(x.url) or 0) < (cidFromUrl(y.url) or 0)
  end)
  return finalizeToc(chapters)
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter text — /read/{bid}/{cid}
-- ═══════════════════════════════════════════════════════════════════════════
-- Content lives in div#nr1 as <p> paragraphs. The site interleaves ad DIVs
-- (.reader-ad carrying loadAdv() scripts) BETWEEN the <p>s INSIDE the
-- content div — selecting only the <p> elements skips every one of them.
-- The h1#nr_title carries a "(cur / total)" sub-page suffix; when total > 1
-- the remaining sub-pages live at /read/{bid}/{cid}/{n} and are fetched and
-- concatenated (defensive — every chapter sampled live was (1 / 1), the
-- sub-page URL shape follows the site's family pattern; a failed sub-page
-- fetch just ends the concatenation with what was gathered).
-- Watermark lines (site domains, (本章完)) are stripped.

local SUBPAGE_CAP = 30

-- "(1 / 2)" → 1, 2 ; also tolerates "(1/2)".
local function parsePageSuffix(title)
  local cur, total = string.match(title or "", "%((%d+)%s*/%s*(%d+)%)%s*$")
  return tonumber(cur), tonumber(total)
end

local function isWatermark(p)
  if p == "(本章完)" or p == "（本章完）" then return true end
  if #p > 80 then return false end
  if string.find(p, "69shuba", 1, true) then return true end
  if string.find(p, "69shuba.tw", 1, true) then return true end
  if string.find(p, "cs76.com", 1, true) then return true end
  return false
end

local function chapterParas(html)
  local el = html_select_first(html, "div#nr1")
  if not el then el = html_select_first(html, ".nr_nr") end
  if not el then return nil end
  local paras = {}
  for _, p in ipairs(html_select(el.html, "p")) do
    local t = string_clean(p.text or "")
    paras[#paras + 1] = t
  end
  if #paras == 0 then
    local raw = string_clean(html_text("<div>" .. el.html .. "</div>"))
    if raw == "" then return nil end
    paras = { raw }
  end
  return paras
end

function getChapterText(html, url)
  if type(html) ~= "string" or html == "" then return "" end

  local paras = chapterParas(html)
  if not paras then return "" end

  -- sub-page continuation: title "(cur / total)" with total > 1
  local titleEl = html_select_first(html, "#nr_title")
  local cur, total = parsePageSuffix(titleEl and titleEl.text or "")
  if cur and total and total > 1 and cur < total and cur < SUBPAGE_CAP then
    local bid = string.match(url or "", "/read/(%d+)/%d+")
    local cid = string.match(url or "", "/read/%d+/(%d+)")
    if bid and cid then
      for n = cur + 1, math.min(total, SUBPAGE_CAP) do
        local r = httpGetPage(SITE .. "/read/" .. bid .. "/" .. cid .. "/" .. tostring(n))
        if not (r and r.success) then break end
        local more = chapterParas(r.body)
        if not more or #more == 0 then break end
        for _, t in ipairs(more) do paras[#paras + 1] = t end
      end
    end
  end

  local out = {}
  for _, p in ipairs(paras) do
    if p ~= "" and not isWatermark(p) then out[#out + 1] = p end
  end
  if #out == 0 and #paras > 0 then
    -- never return an empty chapter (a reader error) — fall back to raw
    for _, p in ipairs(paras) do
      if p ~= "" then out[#out + 1] = p end
    end
  end
  return table.concat(out, "\n\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Engine hooks + settings
-- ═══════════════════════════════════════════════════════════════════════════

function getUserAgentPreset()
  return "Chrome Mobile"
end

function getSettingsSchema()
  return {
    {
      key = PREF_MODE,
      type = "select",
      label = "Mode (模式)",
      current = getMode(),
      options = {
        { value = "raw",       label = "Raw (原文) — Chinese UI, no translation" },
        { value = "translate", label = "Translator (翻譯模式) — translate everything except chapter text" }
      }
    },
    {
      key = PREF_TLANG,
      type = "select",
      label = "Translate To (目標語言)",
      current = getTl(),
      options = {
        { value = "en", label = "English" },
        { value = "es", label = "Español" },
        { value = "pt", label = "Português" },
        { value = "ru", label = "Русский" },
        { value = "fr", label = "Français" },
        { value = "de", label = "Deutsch" },
        { value = "tr", label = "Türkçe" },
        { value = "ar", label = "العربية" },
        { value = "id", label = "Bahasa Indonesia" },
        { value = "th", label = "ไทย" },
        { value = "vi", label = "Tiếng Việt" },
        { value = "ja", label = "日本語" },
        { value = "ko", label = "한국어" },
        { value = "hi", label = "हिन्दी" },
        { value = "ur", label = "اردو" }
      }
    },
    {
      key = PREF_TR_CH,
      type = "select",
      label = "Translate Chapter Titles (章節標題)",
      current = trChaptersEnabled() and "1" or "0",
      options = {
        { value = "1", label = "On (開)" },
        { value = "0", label = "Off (關)" }
      }
    }
  }
end
