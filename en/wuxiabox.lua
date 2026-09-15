-- ═══════════════════════════════════════════════════════════════════════════
-- WuxiaBox source plugin for NoveLA  (https://www.wuxiabox.com)
-- File: en/wuxiabox.lua — Version 2.0.0 (2026-09-15)
-- Upgrades the community plugin en/wuxiabox.lua v1.0.1 in place (same
-- source id "wuxiabox"). Book URLs are unchanged (same site, same
-- /novel/{slug}.html addresses), so existing libraries carry over.
--
-- 2.0.0 (2026-09-15) — MAJOR UPGRADE of the WuxiaBox plugin. The base
--     v1.0.1 (HnDK0/external-sources) was re-verified function by function
--     against live pages and every behavior worth keeping was carried over;
--     the plugin gained the full tag index, a working search pipeline, and
--     self-healing chapter fetching. Details below.
--
--   UPGRADE NOTES vs BASE v1.0.1
--   • KEPT from v1.0.1 (verified against live HTML): the one-run page
--     cache shared by all book getters; XHR headers on fy.php chapter
--     fragments; cover data-src → src fallback; p.description selector
--     preference; relative-date normalization ("5 hours ago" → date);
--     html_remove selector set (scripts/styles/ads/iframes — merged with
--     the v2 set); "(End of this chapter)" marker removal; the
--     WuxiaBox branding / Chapter-echo / translator-credit line cleaners
--     (merged and extended).
--   • FIXED from v1.0.1:
--       – Status filter values were lowercase ("ongoing"/"completed") but
--         the site's list URLs are capitalized — its own filter links go to
--         /list/all/Completed-newstime-0.html and /list/all/Ongoing-
--         lastdotime-0.html. The old status filter silently did nothing.
--       – getBookDescription preferred <p class="description">, which the
--         site renders EMPTY on novel pages (the real synopsis lives in
--         .summary .content) — and since "" is truthy in Lua, the old
--         code returned empty descriptions. The selector preference is
--         kept, but empty results now fall through to .summary .content.
--       – getBookLastUpdate read the last <time> of the embedded chapter
--         list — but the novel page embeds the OLDEST 100 chapters, so any
--         novel longer than 100 chapters got a stale update date. The date
--         now comes from the newest chapter on the LAST fy.php page (one
--         cached fragment request), with the old behavior as fallback.
--       – Search relied on the engine following the POST redirect and had
--         no result pagination (see "Improved search" below).
--   • Supersedes the interim "wuxiaworld_site.lua v2.0.0" build (2026-09-14)
--     which was mistakenly targeted at the wuxia_world_site slot — that
--     slot belongs to the separate WuxiaWorld.site (Madara) source. If you
--     installed that build, remove it and install this file instead.
--
--   WHAT'S NEW
--   • ALL site tags (see TAG_SEARCH_INDEX below) harvested from
--     https://www.wuxiabox.com/browsetags/ and shipped as a searchable
--     index: the "Tag Search" filter takes any keyword ("system",
--     "male prot", "ancient") and resolves it to EVERY tag whose name
--     contains it — matching is case-insensitive AND space-insensitive
--     ("maleprot" == "Male Protagonist"), so the site's squashed tag
--     names (AncientChina, MaleProtagonist…) are found either way.
--     Numeric tag ids ("34") and "prefix*" wildcards also work.
--     Multiple keywords: comma-separated, all resolved tags are merged.
--     The plugin then browses the tag listings (one request per tag,
--     lightly paced) and merges the results — "everything as search
--     result", the way the site's own tag pages work.
--     Tag Search Category = A-Z letter scope (the site groups tags by
--     first letter on /browsetags/).
--   • Full filter parity with the site's "Categories" browser:
--     57 categories × status (All/Completed/Ongoing) × sort
--     (Newest Added / Last Updated / Most Viewed), plus an "Updates"
--     browse mode (recently updated novels, /updates/).
--   • Improved search: the site's search is an EmpireCMS POST form
--     (/e/search/index.php, fields show=title&tempid=1&tbname=news&
--     keyboard=…) that 302-redirects to /e/search/result?searchid=N.
--     NoveLA's http_post does NOT follow redirects, so the old-style
--     "POST and parse" never worked here — the plugin now follows the
--     redirect chain manually (Location header, up to 3 hops), falls
--     back to the GET searchget=1 variant, and supports result
--     pagination (/e/search/result/index.php?page=N&searchid=S,
--     20 items/page, total count parsed from the pager).
--   • "502 Bad Gateway every ~2 chapters" FIX (root cause): a 502/504
--     page from the origin parses fine as HTML, so the app fetched it,
--     got empty text from the plugin, and DownloaderRepository's retry
--     loop classified the failure as non-transient (it only retries
--     timeout/connect errors) — the chapter just failed. The plugin now
--     detects chapter pages without real content (#chapter-article /
--     .chapter-content missing → error/interstitial page) and REFETCHES
--     the chapter itself with exponential backoff (default 4 attempts:
--     ~0.9s / 2.8s / 6.3s waits + jitter), which rides out the site's
--     transient origin flaps. A configurable pacing floor (default
--     1500 ms between chapter requests, os_time is millisecond-
--     resolution in NoveLA) additionally keeps sequential reading from
--     hammering the origin.
--   • Chapter list via parsePage (paginated): the novel page holds the
--     first 100 chapters (ascending); further pages load from
--     /e/extend/fy.php?page=N-1&wjm={slug} (HTML fragment, 100/page).
--     parsePage gives the engine incremental updates (re-reads only the
--     last page on library refresh) instead of re-fetching everything.
--   • Chapter text cleanup: ad <script>s removed, the novel-title /
--     "Author:" / "Synopsis:" echo paragraphs that the site prepends
--     to every chapter are stripped, standard site-reference/translator
--     lines removed, paragraphs preserved via html_text.
--
--   SITE MAP (verified 2026-09-14 against live HTML)
--   • Catalog list      GET  /list/{category}/{status}-{sort}-{page}.html
--                        category: all + 57 slugs · status: all|Completed|Ongoing
--                        sort: newstime (added) | lastdotime (updated) | onclick (views)
--                        page is 0-based, 30 items/page, ~104 000 novels
--   • Tag browse        GET  /tags/{tagid}-0.html (first page, 500 items)
--                        GET  /e/tags/index.php?page={N}&tagid={id}&line=500&tempid=9
--                        total count in the pager: <a title="总数"><b>N</b></a>
--   • Updates           GET  /updates/ then /updates/{N}.html (0-based, 50/page,
--                        cards link to the LATEST chapter — url rewritten to the novel)
--   • Search            POST /e/search/index.php (show=title&tempid=1&tbname=news&keyboard=…)
--                        → 302 → /e/search/result?searchid=S (20/page)
--                        pages: /e/search/result/index.php?page={N}&searchid=S
--                        GET variant: /e/search/?searchget=1&keyboard=…&show=title&tbname=news&tempid=1
--   • Novel page        GET  /novel/{slug}.html
--                        header.novel-header → h1.novel-title · figure.cover img[data-src]
--                        .author span[itemprop=author] · .header-stats (Chapters/Status)
--                        .categories → a.property-item (genres) + a.tag (tags, full names)
--                        #info → p.description (renders EMPTY; fallback) →
--                        .summary .content (real synopsis) · .tags ul.content (tag chips)
--   • Chapter list      novel page (chapters 1-100, ascending) +
--                        /e/extend/fy.php?page={N-1}&wjm={slug} fragments (100/page)
--   • Chapter page      GET  /novel/{slug}_{n}.html → #chapter-article .chapter-content
--                        (.titles h1 = novel title link, h2 = chapter title)
--
--   NOTES / LIMITS
--   • wuxiabox.com sits behind a Cloudflare managed challenge. NoveLA's
--     CloudfareVerificationInterceptor already auto-solves challenges via
--     the integrated WebView for every plugin http_get/http_post — do NOT
--     add cf_options (see wtrlab.lua docs; whitelist=true disables the
--     recovery path).
--   • The origin behind Cloudflare intermittently returns 502/504 —
--     that is what the in-plugin chapter retry + pacing address. The app
--     also issues two HTTP hits per chapter (one URL-resolve pass + one
--     document fetch in DownloaderRepository.bookChapter), which makes
--     the pacing floor all the more useful.
--   • Tag exclusion is NOT offered: the site cannot exclude tags via any
--     URL, and novel cards do not carry their tag list, so client-side
--     exclusion would require fetching every novel page.
--   • The site has no numeric ratings; getBookRating is intentionally
--     not implemented.
--   • Tag labels in /browsetags/ are truncated to 10 chars by the site
--     itself (AncientChi, AdaptedtoM…). The build script expands them to
--     full spaced names when the prefix is unambiguous; the in-plugin
--     search is space-insensitive regardless.
--
--   TAG INDEX MAINTENANCE: regenerate with
--     scripts/harvest_wuxiabox_tags.py  (resumable live harvest)
--     scripts/build_wuxiabox_tag_index.py  (dedup → name expansion →
--     splice into TAG_SEARCH_INDEX below), then re-run the harness
--     (test-harness/WuxiaboxTest.java). The full pipeline is documented
--     in wuxiabox_pull_request.md § 9.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "wuxiabox"
name     = "WuxiaBox"
version  = "2.0.0"
baseUrl  = "https://www.wuxiabox.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/wuxiabox.png"

local SITE = baseUrl

-- ── Settings keys ───────────────────────────────────────────────────────────
local PREF_RETRY = "wuxiabox_chapter_retries"
local PREF_PACE  = "wuxiabox_chapter_pace_ms"

local function getRetryCount()
    local v = tonumber(get_preference(PREF_RETRY))
    if v and v >= 1 and v <= 6 then return math.floor(v) end
    return 4
end

local function getPaceMs()
    local v = tonumber(get_preference(PREF_PACE))
    if v and v >= 0 and v <= 10000 then return math.floor(v) end
    return 1500
end

-- ── Small helpers ───────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(SITE, href)
end

-- First value of a response header (NoveLA marshals headers as a
-- multimap: r.headers["location"] = {"https://…"}).
local function headerFirst(headers, name)
    if type(headers) ~= "table" then return nil end
    local v = headers[name] or headers[string.lower(name)]
    if type(v) == "table" then
        return (v[1] ~= nil and v[1] ~= "") and v[1] or nil
    elseif type(v) == "string" then
        return v ~= "" and v or nil
    end
    return nil
end

-- /novel/{slug}.html → "slug" ; /novel/{slug}_{n}.html → "slug"
local function novelSlug(url)
    if not url then return nil end
    return string.match(url, "/novel/([^/?#]+)%.html")
end

local function chapterToNovelUrl(chapterUrl)
    local slug = novelSlug(chapterUrl)
    if not slug then return chapterUrl end
    return SITE .. "/novel/" .. slug .. ".html"
end

-- ── Page cache (one engine run) ─────────────────────────────────────────────
-- All book-detail getters + parsePage(page 1) + getBookLastUpdate share the
-- novel page fetch through this cache (the engine calls the getters in
-- parallel). fy.php fragment fetches are cached here too.

local _pageCache = {}

local function fetchPage(url, headers)
    if _pageCache[url] then return _pageCache[url] end
    local r
    if headers then
        r = http_get(url, { headers = headers })
    else
        r = http_get(url)
    end
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

-- EmpireCMS AJAX fragment endpoints (fy.php) expect an XHR request.
-- Carried over from the community wuxiabox.lua v1.0.1.
local FY_HEADERS = {
    ["X-Requested-With"] = "XMLHttpRequest",
    ["Accept"]          = "text/html",
}

-- ── Request pacing ──────────────────────────────────────────────────────────
-- os_time() in NoveLA is System.currentTimeMillis() → millisecond precision.
-- A floor between chapter requests keeps sequential reading (and downloads)
-- from hammering an origin that intermittently 502s under load.

local _lastChapterTs = 0

local function chapterPacing()
    local gap = getPaceMs()
    if gap <= 0 then return end
    local now = os_time()
    local elapsed = now - _lastChapterTs
    if elapsed >= 0 and elapsed < gap then
        sleep(gap - elapsed)
    end
    _lastChapterTs = os_time()
end

-- Light pacing for multi-request browse paths (tag union, fy pages).
local _lastBrowseTs = 0

local function browsePacing(gap)
    gap = gap or 400
    local now = os_time()
    local elapsed = now - _lastBrowseTs
    if elapsed >= 0 and elapsed < gap then
        sleep(gap - elapsed)
    end
    _lastBrowseTs = os_time()
end

-- ── Error / interstitial page detection ─────────────────────────────────────
-- A real chapter page always contains #chapter-article .chapter-content.
-- Cloudflare "Just a moment…", nginx 502/504, and the site's "Maintenance"
-- interstitial do not. The engine hands exactly such bodies to
-- getChapterText when the origin flaps (the app's own retry loop only
-- retries timeout/connect errors, so a 502 page reached the plugin).

local function isChapterErrorPage(html)
    if not html or html == "" then return true end
    if html_select_first(html, "#chapter-article .chapter-content") then return false end
    if html_select_first(html, ".chapter-content") then return false end
    return true
end

-- Refetch a chapter URL with exponential backoff + jitter. Every attempt
-- goes through the app's OkHttp stack, so the CloudfareVerification
-- interceptor keeps working (challenges → WebView bypass → retry).
local function refetchChapterWithRetry(chapterUrl)
    local attempts = getRetryCount()
    local novelUrl = chapterToNovelUrl(chapterUrl)
    for attempt = 1, attempts do
        if attempt > 1 then
            local waitMs = 900 * attempt * attempt + math.random(0, 400)
            sleep(waitMs)
        else
            sleep(700 + math.random(0, 300)) -- brief pause before the first retry
        end
        local r = http_get(chapterUrl, {
            headers = {
                ["Referer"] = novelUrl,
                ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            }
        })
        if r.success and not isChapterErrorPage(r.body) then
            log_info("wuxiabox: chapter refetch succeeded on attempt " .. attempt .. ": " .. chapterUrl)
            return r.body
        end
        log_error("wuxiabox: chapter fetch attempt " .. attempt .. "/" .. attempts ..
            " failed (code " .. tostring(r.code) .. "): " .. chapterUrl)
    end
    return nil
end

-- ── Relative date normalization ("5 hours ago" → YYYY-MM-DD) ────────────────

local function normalizeUpdateDate(raw)
    if not raw or raw == "" then return nil end
    local n, unit = string.match(raw, "(%d+)%s+(%w+)%s+ago")
    if not n then return nil end
    local mult = {
        minute = 60, minutes = 60,
        hour   = 3600, hours = 3600,
        day    = 86400, days = 86400,
        week   = 7 * 86400, weeks = 7 * 86400,
        month  = 30 * 86400, months = 30 * 86400,
        year   = 365 * 86400, years = 365 * 86400,
    }
    local secs = mult[string.lower(unit)]
    if not secs then return nil end
    return os.date("%Y-%m-%d", os.time() - tonumber(n) * secs)
end

-- ── Content transforms ──────────────────────────────────────────────────────

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = SITE:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    -- Bare branding lines ("WuxiaBox — Read …") without the domain suffix
    -- — kept from base v1.0.1 (\b so "WuxiaBoxian" story words survive).
    text = regex_replace(text, "(?im)^\\s*wuxiabox\\b[^\\n\\r]*$", "")
    -- Standalone "Chapter N …" echo lines ANYWHERE in the body (the site
    -- repeats them at split points) — kept from base v1.0.1, now also in
    -- Russian (Глава) and anchored per line.
    text = regex_replace(text, "(?im)^\\s*(Chapter|Глава)\\s+\\d+[^\\n\\r]*$", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    -- Credit lines with a colon: base v1.0.1's set (incl. T/N, E/N and the
    -- Russian variants) + proofreader.
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|T/N|E/N|Перевод|Редакция)\\s*:\\s*[^\\n\\r]{0,120}(\\r?\\n|$)", "")
    -- "Read at / on / latest …" watermarks.
    text = regex_replace(text, "(?im)^\\s*Read\\s+(at|on|latest)[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    -- Site-specific: the chapter body repeats the novel title / Author /
    -- Synopsis echo lines at the top of every chapter.
    text = regex_replace(text, "(?im)^\\s*(Author|Synopsis|P\\.?S\\.?)[:\\s][^\\n\\r]{0,160}(\\r?\\n|$)", "")
    return string_trim(text)
end

-- Strip the leading novel-title echo paragraph (the site prepends the book
-- title as the first <p> of every chapter). The real title is parsed from
-- the same page (.titles h1) so no extra request is needed.
local function stripTitleEcho(text, pageHtml)
    local h1 = html_select_first(pageHtml, ".titles h1")
    if h1 then
        local title = string_clean(h1.text)
        if title ~= "" then
            -- Compare the first text line with the title, ignoring
            -- case/spacing/punctuation ("Bengtie: A Genius's Idea" ==
            -- "bengtie a geniuss idea").
            local firstLine = text:match("^(.-)\n") or text
            local function flat(s)
                s = string.lower(s)
                s = s:gsub("[%s%p%s+]", "")
                return (s:gsub("^%s+", ""))
            end
            local a, b = flat(firstLine), flat(title)
            if a ~= "" and (a == b or string.find(b, a, 1, true) or string.find(a, b, 1, true)) then
                text = text:gsub("^[^\n]*\n?", "", 1)
            end
        end
    end
    return text
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TAG SEARCH INDEX
-- One "id|Label|L" triple per line, auto-generated from the live
-- https://www.wuxiabox.com/browsetags/ pages (all letters, all pages) by
-- scripts/build_wuxiabox_tag_index.py. Labels are the site's own names;
-- where the site truncates to 10 chars, the build script expands to the
-- full spaced name when the prefix is unambiguous. L is the letter page
-- the tag lives on (pinyin letter for the site's Chinese tags: 报仇 → B).
-- Do not hand-edit — re-run the generator after refreshing the harvest.
--
-- Parsed once at plugin load into ALL_TAGS:
--   { id = "34", label = "Ancient China", lower = "ancient china",
--     flat = "ancientchina", letter = "A" }
--   flat = lowercased label with ALL whitespace removed — the match key
--   that makes the search space-insensitive.
-- ═══════════════════════════════════════════════════════════════════════════

local TAG_SEARCH_INDEX = [==[
-- BEGIN_TAG_INDEX (auto-generated — do not edit)
4862|A.I|A
6070|a55421|A
2064|Aaron&0|A
5017|AbaloneHou|A
145|Abandoned Children|A
5452|Abandoned Children|A
1597|Abandoned Children|A
3327|abandonedw|A
1691|Abilities|A
1203|Ability Steal|A
289|Ability Steal|A
930|ABO|A
1696|Abortion|A
4168|ABowlofCar|A
4398|Abowlofduk|A
240|Absent Parents|A
1670|AbsoluteDu|A
2255|absolutely|A
3681|Absorbform|A
856|Abuse|A
6505|Abuseofscu|A
6317|Abuseofscu|A
1|Abusive Characters|A
815|Abusive Characters|A
3971|Abyss|A
6238|Academic|A
6578|AcademicSt|A
50|Academy|A
6155|Academystr|A
5993|Acane|A
4689|acanofcoke|A
806|AcasualPaw|A
51|Accelerated Growth|A
1507|AcceptingD|A
1653|ACGN|A
4002|acloudpier|A
6734|Acomeback|A
5910|Acorneroft|A
103|Acting|A
6712|Actingonbe|A
90|Action|A
1101|Actors|A
1526|Actress|A
4815|Acupoffrag|A
3745|acupofwarm|A
87|Adapted to Anime|A
334|Adapted to Game|A
973|Adapted to Visual Novel|A
6203|Adaptedfro|A
146|AdaptedtoD|A
495|AdaptedtoD|A
88|AdaptedtoM|A
239|AdaptedtoM|A
677|AdaptedtoM|A
147|AdaptedtoM|A
5069|ADeadBody|A
5659|Administra|A
4680|Admiral-sa|A
1300|Adopted|A
262|Adopted Children|A
270|Adopted Protagonist|A
1697|Adoption|A
4569|adreamcome|A
1105|Adrogynous|A
433|Adultery|A
1448|Adultery|A
1564|AdvancedKn|A
1661|advancedte|A
3416|adventerer|A
3942|adventurep|A
943|Adventurers|A
276|Adventurers|A
4342|Adventurers|A
6163|Aesthetic|A
670|Affair|A
6681|Affection|A
5843|afigure|A
4804|afinegray|A
1894|AfricanEmi|A
6413|Aftermarri|A
4489|afterthera|A
3231|Afterthesh|A
1818|Aftertheso|A
3697|Afunnyguy|A
206|Age Progression|A
436|Age Regression|A
1943|Age-gap|A
939|AgeDiffere|A
1642|AgeGap|A
3605|Agent|A
1897|AgeofGods|A
1284|AggresiveC|A
242|Aggressive Characters|A
1476|Aggressive Characters|A
4049|aglassofhu|A
4483|Agleamoffl|A
4884|agluttonou|A
1893|agrass|A
5530|Ahbig|A
4219|aheart|A
3965|AhQing|A
3475|ahundredth|A
1876|ahveryfish|A
788|AI|A
1181|AI-chip|A
5491|AiAiwhowor|A
4923|ailii|A
5897|Aimingatth|A
3266|airflow|A
3051|airflowgen|A
4885|Aishara|A
5892|AJiu|A
5736|ajugofsake|A
1040|AkamegaKil|A
4595|AkiraHayak|A
4536|akitten|A
5873|AladleofCh|A
5295|alazybones|A
4096|alazyscale|A
1000|Alchemist|A
52|Alchemy|A
4557|AliceSupre|A
3758|Alicia|A
6186|Alienbeast|A
3111|Aliens|A
243|Aliens|A
4546|alittlebit|A
4921|AlittleJun|A
4232|alittlewol|A
2656|Aliverday|A
1024|All-Girls School|A
4316|Alldaylong|A
2015|allenzhang|A
3665|allergytoe|A
6576|AllHeavens|A
2348|AllHeavens|A
3897|Alloverthe|A
3265|Almighty|A
2778|AlmightyCo|A
2780|Almightypl|A
4238|Almostsir|A
2610|Alone|A
5616|Alpaca|A
4340|alpha|A
4775|alsothough|A
5298|AltecNewco|A
2902|AlterateHi|A
220|Alternate World|A
1256|AlternateH|A
3026|AlternateH|A
2995|AlternateH|A
2948|AlternateH|A
6444|Alternatin|A
3836|Alternativ|A
6460|Alternativ|A
5792|AmadaR|A
2434|Amagicpill|A
5841|AmanChuanl|A
6129|Amatchmade|A
6059|amateurtra|A
4087|amberstar|A
6467|ambiguous|A
4853|ambitionin|A
5026|Amelonisno|A
3285|America|A
3450|Americaiss|A
2899|AmericanCo|A
2903|Americas|A
5279|Amis|A
244|Amnesia|A
5965|Amnesty|A
3740|Amon&03|A
4877|amoonrabbi|A
1044|AmoralityP|A
3980|Amouthfulo|A
766|Amusement Park|A
5020|An83|A
53|Anal|A
5019|anamewithd|A
3855|Anarchism|A
3764|Anas|A
2577|Anautumnra|A
6235|Ancestors|A
3352|Ancestralf|A
5826|ancestry|A
1546|Ancient|A
34|Ancient China|A
2892|Ancient China|A
424|Ancient China|A
149|Ancient Times|A
1049|Ancient Times|A
5701|AncientArm|A
1257|AncientBus|A
6264|AncientFan|A
5680|ancientlov|A
6150|Ancientmar|A
6204|Ancientpre|A
1478|AncientRea|A
6762|Ancientsay|A
1465|ancientset|A
3235|AncientSpi|A
1730|AncientWea|A
3637|ancientwei|A
3432|ancientwil|A
4373|andfall|A
318|Androgynous Characters|A
471|Androids|A
6127|Angel&0|A
4089|angeldoom|A
4636|AngelofGai|A
4059|AngelPeerl|A
369|Angels|A
1589|Angels|A
5414|anglemetal|A
4426|AngryChick|A
2331|angryhouse|A
1007|Angst|A
120|Animal Characteristics|A
453|Animal Rearing|A
1694|animals|A
1704|Animator|A
759|Anime|A
2208|animenewco|A
189|Anl|A
2842|AnlanInvin|A
6085|AnNuan84|A
3792|anoldliqun|A
2268|anoldman|A
4223|Anon|A
5229|Anonymous|A
5420|Anonymouso|A
4816|AnonymousX|A
4389|anorangetr|A
4138|anotherpac|A
899|AnotherWor|A
6791|AnotherWor|A
1550|AnotherWor|A
5407|anovernigh|A
3820|anti-entro|A
1174|Anti-Hero|A
782|Anti-HeroL|A
1171|Anti-heroP|A
3269|Anti-Japan|A
6551|Anti-Japan|A
688|Anti-Magic|A
2916|Anti-MC|A
3096|Anti-routi|A
3073|Anti-routi|A
454|Anti-social Protagonist|A
6783|Anti-timet|A
36|Antihero Protagonist|A
816|Antihero Protagonist|A
619|Antique Shop|A
6786|Antique Shop|A
5731|AoChen|A
5662|Aoyamafell|A
4811|AozakiAoko|A
4603|apapertige|A
725|Apartment Life|A
4891|apassingfi|A
5913|Apassingfo|A
295|Apathetic Protagonist|A
6339|aperfectwo|A
3498|apieceofno|A
5029|apigeon|A
89|Apocalypse|A
5466|Apocalypse|A
1233|Apocalypse|A
1081|Apocalypse|A
1485|Apocalypti|A
5858|ApostleCel|A
5865|Apotofrefr|A
54|Appearance|A
104|Appearance|A
1962|Apple|A
1180|Appraisal|A
1376|Apprentice|A
3642|aquablue|A
4050|Aquadoesn&|A
2126|arayofsuns|A
3673|Arbor11|A
3629|archeology|A
411|Archery|A
2590|Archery|A
3214|Aresstream|A
221|Aristocracy|A
1150|Aristocrat|A
1598|Aristrocac|A
6595|Arknights|A
1540|Arknights|A
3558|armoredcit|A
6514|Arms Dealers|A
357|Arms Dealers|A
2907|Arms Dealers|A
1389|ArmsTrade|A
329|Army|A
163|Army Building|A
870|Army-build|A
223|Arranged Marriage|A
4344|ArrayMage|A
55|Arrogant Characters|A
6388|Arrogant Characters|A
6440|art|A
5940|ArthurJun|A
209|Artifact Crafting|A
210|Artifacts|A
567|ArtifactsB|A
56|ArtifactsC|A
1755|artificer|A
6585|Artificial Intelligence|A
2919|Artificial Intelligence|A
91|Artificial Intelligence|A
5124|artillery|A
302|Artists|A
869|Artists|A
760|Artists|A
5638|asaltedfis|A
4951|Asasi|A
5497|Ascension|A
6728|ascetic|A
4110|Ashcanfly|A
3803|Ashesthatd|A
4499|ashtrayold|A
4807|AskJianZho|A
2316|askTaichi|A
3497|asmallgras|A
5766|Asmalloffi|A
3423|ASOIAF|A
1763|assasin|A
3462|Assasins|A
5553|assassin95|A
217|Assassins|A
1055|Assassins|A
5519|Aston|A
5477|astonelion|A
700|Astrologers|A
4803|Asukatired|A
5103|asword|A
4617|aswordbone|A
4395|atabbycat|A
3275|athlete|A
3484|AThousandM|A
5763|ATom|A
1832|atravellin|A
1648|Attractive|A
4203|aturkey|A
2298|Auspicious|A
4443|AuthorJi|A
2018|Authoroffa|A
241|Autism|A
1639|AutomaticU|A
1312|AutomaticU|A
675|Automatons|A
1838|autumnautu|A
4142|autumncold|A
5436|autumnisno|A
4518|AutumnLeav|A
3685|autumnleav|A
3698|Avatar|A
1635|Avatar&|A
245|Average-looking Protagonist|A
905|AverageLoo|A
2466|avigorous|A
5715|Awakeningf|A
985|Award-winning Work|A
5517|awhitebait|A
271|Awkward Protagonist|A
2066|Ayanokoji|A
5241|Ayres|A
2637|AZanpakut|A
1702|Azeroth|A
5954|azure|A
1068|AzurLane|A
3862|babbling1|B
1223|Babies|B
3594|baby|B
4278|BabyFeng|B
6475|Backroom|B
4479|backtoboat|B
1695|Badassprot|B
4584|badcheese|B
5977|Bagpipeson|B
5427|BaiBailan~|B
5472|BaiMaoisno|B
4875|BaiMingxia|B
4995|BaiTuanJiu|B
2820|BaiXiaowei|B
4432|BaiYuenake|B
2395|baldman|B
5207|Baldmaster|B
2313|baldnessat|B
5628|BaldTraine|B
2830|balduncle|B
5189|BalmoreBea|B
3654|bamboobamb|B
4506|BambooFlow|B
4918|bambooink|B
5643|bambooshad|B
5776|Bambooskin|B
3302|Bandit|B
2260|BarrenEmpe|B
673|Baseball|B
579|Based on a Movie|B
1118|Based on a Song|B
671|Based on a TV Show|B
1052|Based on an Anime|B
1014|BasedonaVi|B
1083|BasedonaVi|B
5653|BashuiDuxi|B
226|Basketball|B
3068|Basketball|B
1606|Basketball|B
4912|BatDemonCh|B
6404|Battle|B
416|Battle Academy|B
211|Battle Competition|B
6403|battlefiel|B
6661|battleofwi|B
1333|BattleThro|B
5375|Baumudrich|B
4765|BBQmadebyt|B
190|BDSM|B
2508|beaming|B
2786|Beansandgr|B
2142|Bearcat|B
3461|BearChild|B
2232|Bearchildl|B
2652|bearcocoa|B
5798|beardada|B
4253|beardwhite|B
1253|Beast|B
57|Beast Companions|B
1128|Beast Companions|B
8|Beastkin|B
1700|beastman|B
1369|Beastmen|B
2315|beastprota|B
58|Beasts|B
6684|BeastStrea|B
1254|Beasttamer|B
5057|Beasttamin|B
6614|BeastTamin|B
3441|beastworld|B
5170|Beat|B
5065|Beatthefem|B
5064|Beatthemal|B
2204|beatyourse|B
21|Beautiful Female Lead|B
6200|Beautiful Female Lead|B
1748|Beautiful Female Lead|B
1746|Beautiful Female Lead|B
1456|Beautiful Female Lead|B
2691|beautifula|B
5870|Beautifulb|B
1018|BeautifulC|B
6634|Beautifulg|B
59|beautifulh|B
1516|Beautifull|B
1160|BeautifulP|B
1418|beauty|B
4560|Beautyred|B
2649|becausesoh|B
3215|becomeagod|B
3022|becomeagod|B
1921|Becomefamo|B
6510|Becomingad|B
6405|Becomingan|B
4790|BeefandShr|B
6356|beggar|B
2710|beggingfor|B
5878|Beginner|B
4836|Behappytod|B
1643|BehindtheS|B
6230|Behindthes|B
1505|BehindtheS|B
3945|BeichengNa|B
6050|BeidouTian|B
5421|BeiHaiPiao|B
6528|Beijing|B
5112|BeishanRai|B
6045|bellbell|B
4568|bellsofjoy|B
2404|Belltouche|B
3117|Bellyblack|B
1992|belovedbab|B
1412|ben10|B
4668|Benson|B
628|Bestiality|B
40|Betrayal|B
5456|Betweenthe|B
5172|Betweenthe|B
2828|bewitching|B
6162|Bgfellow|B
79|Bickering Couple|B
5054|bickeringl|B
6268|bigAdventu|B
5660|bigblue|B
3125|bigbrain|B
802|BigBroHasD|B
5782|bigcatpres|B
4793|bigcatslav|B
5274|bigchinchi|B
2367|bigcitysma|B
2586|Bigcockcut|B
2042|Bigdog|B
3752|bigdreamsa|B
5146|bigfacemor|B
5651|bigfire|B
2683|bighippo|B
4498|bigisbeaut|B
6690|bigman|B
6046|bigorange|B
2319|bigorangew|B
4948|bigpeninth|B
1796|bigpicture|B
1880|Bigplayers|B
3721|BigSesameR|B
2235|BigSkeleto|B
6297|bigtailwol|B
2605|bigtent|B
1911|bigwhitewh|B
1457|Billionair|B
2868|billionpeo|B
4330|billionpoi|B
2140|BingtangHu|B
473|Biochip|B
6325|Biographya|B
1706|Biomass|B
6247|Birth|B
1846|Biscuits|B
813|Bisexual Protagonist|B
5992|Bishamonte|B
5001|BishopMyri|B
6125|bite|B
2212|bitefire|B
857|BL|B
38|Black Belly|B
1053|Black Belly|B
1273|Black-bell|B
925|Black-bell|B
4081|blackabyss|B
2219|blackandim|B
2797|blackandwh|B
1867|blackandwh|B
1556|Blackbelli|B
4572|Blackbirch|B
5509|blackcatam|B
2711|blackcatis|B
2720|BlackDrago|B
3219|Blackening|B
4984|blackflash|B
5203|blackgreen|B
3375|blackice|B
3506|blackInter|B
1707|Blacklight|B
3366|Blacklotus|B
171|Blackmail|B
3973|blackpupil|B
3944|blackpupil|B
4709|blackreinc|B
4014|blacksilkj|B
379|Blacksmith|B
2144|blacksoil|B
4593|blacksword|B
4303|blacktea|B
3866|blackteais|B
5700|Blacktechn|B
4756|BladeofFal|B
3966|blast|B
5739|BlazingAng|B
1123|Bleach|B
1234|Blind|B
3694|Blind Dates|B
676|Blind Dates|B
481|Blind Protagonist|B
4532|blindnomik|B
4139|blindzhang|B
534|Blood Manipulation|B
1541|Bloodborne|B
2095|blooddemon|B
9|Bloodlines|B
1205|Bloodlines|B
2237|BloodMoonG|B
1822|BloodofAni|B
5062|Bloodpumpi|B
6600|bloody|B
5037|bloodytuna|B
1951|bloomingon|B
4598|blowdreamt|B
4455|bluelight|B
5966|bluemoonco|B
6036|bluenight|B
4837|bluepigeon|B
2192|blueshirts|B
2832|bluesilk|B
2675|bluesilksu|B
4495|BlueSkyDem|B
5565|blueskyspa|B
2206|bluestone|B
4269|bluewaterg|B
4333|bluewhale|B
5479|BoboXiaolu|B
3661|Bodhi|B
2507|Bodhicitta|B
269|Body Swap|B
246|Body Tempering|B
980|Body-double|B
439|Bodyguards|B
3701|Bodyguards|B
2793|Boiled|B
5830|Bombardmen|B
1415|book|B
2416|BookDustSp|B
337|Books|B
2922|bookslikeu|B
3907|Booksonthe|B
2133|BookstoreS|B
947|BookTransm|B
1153|BookWearer|B
659|Bookworm|B
2911|Boss-Subordinate Relationship|B
80|Boss-Subordinate Relationship|B
3324|BOSSflow|B
5366|BossSim|B
4486|Botharetwo|B
1030|bottommc|B
3582|bouncingei|B
1982|Boundlessf|B
5622|BoundlessL|B
5041|Bowandjack|B
3902|Bowandshoo|B
2389|BoXiaowen|B
667|Boxing|B
4631|boxser|B
2626|boycold|B
6258|brainburn|B
6259|Brainhole|B
4509|Brainisuna|B
5588|BrainJam|B
396|Brainwashing|B
4839|braisedfis|B
2132|BraisedPai|B
3541|BraisedPis|B
1441|breakingli|B
2565|Breakingth|B
2263|breaktheke|B
1344|Breakup|B
974|Breast Fetish|B
2101|Breeze|B
5290|Breeze&|B
2045|breezesilv|B
5909|Brewingflo|B
5872|BrigadeSec|B
2073|Brightmoon|B
2643|Bringaknif|B
1489|BritishEmp|B
2870|broalwaysg|B
231|Broken Engagement|B
5004|Broken Engagement|B
4153|brokenambi|B
5840|BrokenDanf|B
5543|brokendrea|B
4611|brokendrea|B
5823|brokenfrui|B
4634|brokengodo|B
4397|brokenhear|B
4580|brokenlitt|B
4317|brokenmoon|B
4677|brokenred|B
5525|BrokenYuri|B
4135|BronzeEndo|B
6648|brothel|B
3609|Brother|B
521|Brother Complex|B
2181|BrotherChe|B
570|Brotherhood|B
4346|BrotherInL|B
5395|BrotherQin|B
2227|BrotherZhu|B
5022|Browlin|B
1866|Brownsugar|B
3884|BrutalBeas|B
1288|BTTH|B
5590|Bubble012|B
4802|bubblebath|B
6234|bucket|B
6016|BucketofIn|B
3376|BuddhaofNi|B
442|Buddhism|B
4220|Buddhistco|B
5347|building|B
1764|buildingki|B
1539|BuildKingd|B
2571|Buildthewo|B
4965|bulgingbel|B
1614|Bulldozer|B
134|Bullying|B
786|Bullying|B
2068|BuLofan|B
1773|BungouStra|B
1381|BunguoStra|B
3974|Bunnyeatse|B
4936|Bunsaresol|B
4773|BurningEye|B
4711|BurningEye|B
2703|Burningmou|B
2694|burnout|B
663|Business|B
60|Business Management|B
1069|Business Management|B
962|BusinessDe|B
761|BusinessEm|B
5679|businessfl|B
227|Businessmen|B
954|businessor|B
1814|BusinessRi|B
1514|Bussinesma|B
1450|Bussiness|B
763|Butlers|B
1980|ButterflyD|B
5038|Butterrice|B
6470|Buyahouse|B
4982|BZ|B
4693|C14H18N2O5|C
5829|cabbagebut|C
2640|Caicolorsh|C
6397|Calculatio|C
6382|call|C
3755|callmeknig|C
4993|callmethep|C
2417|callthebea|C
22|Calm Protagonist|C
3164|Calm Protagonist|C
834|CalmMalePr|C
2004|camera|C
6553|campaign|C
1677|Campus|C
1274|CampusLife|C
589|CampusLove|C
2880|CampusRoma|C
3927|can&039|C
5827|can&039|C
4944|can&039|C
3535|Can&039|C
2623|Can&039|C
2409|Can&039|C
4424|Canbeheart|C
2292|Cancat|C
5969|CandiedLem|C
4160|candlecher|C
4996|Candleligh|C
3464|Canepepper|C
2019|canfly|C
4681|CangsongTa|C
2932|CangxueFei|C
407|Cannibalism|C
3350|cannonfodd|C
1985|Canolaflow|C
2782|Cantaloupe|C
2228|Canteendry|C
5032|Canyoustop|C
5666|Caothiefne|C
1490|Capitalism|C
3290|captain|C
4587|captaindra|C
6031|Captainoft|C
6101|carafe|C
2700|CarambolaJ|C
512|Card Games|C
1379|Card Games|C
4861|CardinalSa|C
4692|cardleague|C
564|Cards|C
6478|Career|C
1061|CareerOrie|C
121|Carefree Protagonist|C
122|Caring Protagonist|C
1553|CaringMale|C
4641|Carola|C
5453|carpenter|C
5724|CarrotCake|C
5804|carrotsdon|C
2168|cartoonwil|C
5559|CastlePeak|C
5282|CastlePeak|C
4125|Casual|C
5364|Cat|C
4730|CatCarMK2|C
4881|catcatfrui|C
5071|CatchaGhos|C
3359|catchfast|C
2141|Catchtheca|C
4030|catchthecl|C
1895|catdaylist|C
4535|cateatingp|C
2787|cateatingp|C
4579|caterpilla|C
2470|catgod|C
5741|catheadsan|C
4900|catisland|C
5760|Catisnotat|C
2568|catisrisin|C
2536|catloveson|C
4122|catontheba|C
3648|catorange|C
2624|catpowerfi|C
5753|Catsandcat|C
2271|Catswithfi|C
2022|catthatwan|C
2333|catthousan|C
5795|catwatchin|C
5138|catwithbla|C
4849|catworship|C
6429|cause|C
222|Cautious Protagonist|C
3193|Cautious Protagonist|C
1095|CautiousMc|C
2131|caviar|C
4511|ccc|C
23|Celebrities|C
880|Celebrity|C
5563|celeryeats|C
1439|celestial|C
2608|CelestialC|C
799|Celestials|C
1008|CEO|C
3653|Ceobeisthe|C
2889|ChainsawMa|C
6385|challenge|C
2368|championge|C
3631|chanceenco|C
5949|Chang&0|C
6775|changedest|C
5511|changedhea|C
2223|Changeever|C
4118|ChangGuxue|C
4305|Chanyi|C
4100|ChaoGezi|C
5750|ChaoPrimeM|C
1360|Chaos|C
3123|Chaotang|C
3282|ChaotangJi|C
5788|chaotichea|C
6425|Chaotictim|C
1882|chaoticwor|C
61|Character Growth|C
341|CharacterD|C
3774|chargingca|C
39|Charismatic Protagonist|C
1041|Charlotte(|C
520|Charming Protagonist|C
3597|chase|C
6249|ChasingLov|C
2777|chasingthe|C
3330|chasingwif|C
142|Chat Rooms|C
1757|Chat Rooms|C
1285|chat-room|C
890|ChatGroup|C
3668|chatter|C
6149|cheating|C
62|Cheats|C
888|Cheats|C
5534|Cheesemous|C
5478|Cheesesnow|C
2097|chef&03|C
3818|ChefEmiya|C
260|Chefs|C
829|Chefs|C
2174|ChefSurviv|C
2342|ChenChangf|C
5734|ChenChen|C
4608|ChenDashun|C
4718|Chengnanex|C
5443|ChengWangH|C
1708|ChenHegao|C
3736|ChenShiAi|C
6053|ChenTing|C
2122|ChenTwelve|C
4566|ChenYibing|C
5363|ChenZijin|C
1965|CherryBlos|C
4675|Chestnutca|C
5105|chestnutch|C
6017|ChevaRoy|C
4154|chiccatles|C
4754|ChicSu|C
1966|ChiDongdon|C
3699|chief|C
3663|ChiefScien|C
4332|Chika|C
4193|child|C
393|Child Abuse|C
491|Child Protagonist|C
1074|Childbirth|C
81|Childcare|C
197|Childhood Friends|C
3378|Childhood Friends|C
176|Childhood Love|C
588|Childhood Promise|C
1622|ChildhoodE|C
590|ChildhoodS|C
1155|ChildhoodS|C
123|Childish Protagonist|C
3549|ChinaEnter|C
1705|ChinaNamba|C
1357|ChinaRefor|C
1675|Chinese|C
1692|ChineseAnc|C
6213|Chinesemar|C
3166|Chinesemed|C
1679|ChineseNov|C
1303|ChinesePre|C
1843|Chirika|C
4872|Chirpingan|C
1669|Chivalryof|C
3874|Chiyudoesn|C
1922|ChocolateI|C
1308|ChoiceSele|C
6713|Chongzhen|C
2533|Chosen12|C
5155|chromatics|C
6169|Chronicles|C
1451|Chronology|C
6374|Chugoku|C
5605|chugong|C
5200|Chunghwape|C
6741|Chunichi|C
1390|ChuningMC|C
1359|Church|C
713|Chuunibyou|C
5573|ChuXiaNo.X|C
2340|Cicadasand|C
5755|CinderHand|C
5021|CiShuhua|C
4533|CitrusRoas|C
6130|city|C
2288|CityGod|C
4819|CitySky1|C
6159|Cityurban|C
2738|city​​ya|C
2562|civetcatat|C
3329|Civilizati|C
1775|Civilizati|C
1613|Civilizati|C
3221|civilizati|C
1491|CivilServa|C
6168|ciweimao|C
327|Clan Building|C
1316|ClanSectDe|C
6438|Classic|C
3112|ClassicXia|C
3086|ClassicXia|C
2946|ClassicXia|C
4476|Cleaningfi|C
3338|clear|C
3237|clearthink|C
92|Clever Protagonist|C
373|Clever Protagonist|C
1142|CleverMc|C
297|Clingy Lover|C
4292|Clivia|C
644|Clones|C
4976|cloud-like|C
2771|cloudmadeo|C
5106|cloudpierc|C
2047|Cloudseest|C
2000|CloudSummi|C
2092|Cloudtopfi|C
2202|Cloudtop丨|C
2137|CloudTop丨|C
1948|CloudTop丨|C
4674|cloudymoon|C
1926|cloudysky|C
611|Clubs|C
1583|Clubs|C
1322|Cluelessly|C
1365|CluelessPr|C
204|Clumsy Love Interests|C
1663|cluthullu|C
6078|ClydeVirgi|C
1031|Cnnilingus|C
662|Co-Workers|C
3553|coach|C
4228|cobrasnake|C
2726|cockroache|C
5983|Cocoawithf|C
1772|codegeass|C
2746|Codeuntilt|C
4179|CodewordG|C
2693|codewordge|C
4201|codewordgi|C
4919|codewordna|C
2046|coffeefatc|C
2525|coffeeinst|C
4230|coffeevi|C
1802|coffeewith|C
152|Cohabitation|C
2461|CokeII|C
84|Cold Love Interests|C
1106|Cold Love Interests|C
10|Cold Protagonist|C
2473|coldcolddo|C
4128|coldinearl|C
904|ColdMaleLe|C
1033|ColdMalePr|C
2819|ColdNightL|C
5219|coldnoodle|C
2106|coldrivers|C
4200|coldsalted|C
1871|ColdStar&a|C
3297|collapse|C
6757|Collection of Short Stories|C
749|Collection of Short Stories|C
1454|College/University|C
976|CollegeorU|C
3095|CollegeStr|C
2940|CollegeStr|C
169|CollegeUni|C
1201|Colonializ|C
858|Colonizati|C
5006|colorfasti|C
4182|colorfulcl|C
5425|colorless|C
105|Coma|C
154|Comedic Undertone|C
926|Comedic Undertone|C
878|comedy|C
2112|Comeon|C
1567|Comic|C
6002|ComicMonst|C
1423|comics|C
722|Coming of Age|C
810|Commandand|C
3200|commander|C
4163|Commanderd|C
5384|commemorat|C
950|CommonerLi|C
6670|commonsens|C
1286|Companies|C
6498|Company|C
3928|Competingf|C
1607|Competitio|C
1422|competitiv|C
1134|Complaint|C
5278|Completebo|C
6412|Complex Family Relationships|C
956|Complex Family Relationships|C
253|Complex Family Relationships|C
1291|Complicate|C
3190|comprehens|C
3119|Comprehens|C
6172|Comprehens|C
5341|comprehens|C
3071|Comprehens|C
3047|comprehens|C
3041|Comprehens|C
3021|comprehens|C
3003|comprehens|C
2974|comprehens|C
2969|Comprehens|C
2952|Comprehens|C
2243|Comprehens|C
5972|Conan|C
4187|Conan&0|C
5604|Conanadrea|C
5946|Conanisnot|C
6113|ConantheTh|C
3802|ConanXiang|C
5367|ConchBay|C
3255|concubine|C
445|Conditional Power|C
232|Confident Protagonist|C
172|Confinement|C
541|Conflicting Loyalties|C
3384|Confuciani|C
6593|confused|C
5637|confusedfi|C
5059|Conquer|C
6675|Conquest|C
6664|consecrati|C
4001|Conservati|C
3435|Conspiracy|C
1515|Conspirati|C
6337|constable|C
1113|Constructi|C
1709|Contagonis|C
1400|contempora|C
3093|Contendfor|C
5699|Contest|C
3600|contractlo|C
952|ContractLo|C
3134|contractma|C
2959|contractma|C
294|Contracts|C
1163|Contracts|C
3455|Contrastcu|C
6516|Control|C
161|Cooking|C
3317|Cooking|C
3735|coolandhan|C
5918|Coolchubby|C
4383|coolinocto|C
1050|CoolMc|C
5101|coolmeowma|C
1190|CoolText|C
6427|Cooperatio|C
6795|Coquette|C
3502|corgishort|C
4109|cornisripe|C
2815|cornjuice|C
2663|CorpseFrag|C
408|Corruption|C
338|Cosmic Wars|C
4990|CosmicChar|C
1248|CosmicHorr|C
726|Cosplay|C
3551|cosplaystr|C
6787|counselor|C
1619|Counteratt|C
153|Couple Growth|C
3309|Couple Growth|C
594|Court Official|C
6225|CourtandJi|C
6263|CourtMarqu|C
683|Cousins|C
6329|Coveringth|C
1834|coverthesu|C
290|Cowardly Protagonist|C
1984|coyote|C
3331|CP|C
4085|crackedegg|C
374|Crafting|C
6110|crashreinc|C
4958|Crayfishan|C
5406|Crazy&0|C
3829|crazydream|C
2224|Crazyforam|C
6064|Crazylittl|C
1249|CrazyProta|C
4578|CrazySanMe|C
3652|crazysquid|C
2403|Crazystory|C
4052|createpreh|C
1251|Creation|C
6582|Creationof|C
1549|Creator|C
526|Creatures|C
440|Crime|C
3733|crimesolvi|C
3185|Criminalin|C
173|Criminals|C
832|Criminolog|C
4866|CrimsonFir|C
4746|CrimsonMoo|C
4076|crimsonsku|C
2772|crookeddoo|C
3798|CrookedPay|C
3090|Cross|C
155|Cross-dressing|C
2996|Cross1V1HE|C
3072|Cross1V1st|C
3066|CrossChatg|C
2947|CrossCount|C
1087|Crossdress|C
2944|Crossevery|C
5323|Crossfarmi|C
3007|Crossfarmi|C
2973|Crossfarmi|C
2963|Crossgeniu|C
5307|CrossGiant|C
2971|CrossGoldf|C
2901|Crossing|C
6321|Crossingto|C
3064|CrossInvin|C
2953|CrossInvin|C
2939|CrossInvin|C
3038|Crossmanyf|C
2980|Crossmarti|C
2955|Crossmarti|C
3005|CrossMengB|C
2965|Crossopeni|C
492|Crossover|C
5319|CrossOverh|C
5344|CrossRebir|C
3070|CrossRebir|C
3001|CrossRebir|C
2951|CrossRebir|C
3004|CrossRelax|C
2991|Crossshort|C
2956|CrossSlapC|C
3027|Crosssweet|C
3088|Crosssyste|C
3058|Crosssyste|C
3000|Crosssyste|C
3122|Crosstalka|C
3044|Crosswar|C
3084|Cross空间O|C
2968|Cross空间u|C
5283|crowastron|C
3552|crowmouth|C
42|Cruel Characters|C
2920|Cruel Characters|C
5674|Crush|C
741|Cryostasis|C
1542|Cthulhu|C
916|CubRaising|C
4005|cuckoobunn|C
5302|CuckooChen|C
4741|cucumber|C
1916|CucumberHa|C
6299|CultivateI|C
63|Cultivation|C
3790|Cultivation|C
3417|Cultivation|C
1417|Cultivation|C
1361|Cultivator|C
6766|Culturalre|C
6409|culture|C
164|Cunning Protagonist|C
2897|Cunning Protagonist|C
1568|Cunning Protagonist|C
1232|cunningfem|C
1759|cunningmc|C
2802|Cupola|C
3251|cure|C
3789|curechildr|C
5860|CuredChick|C
261|Curious Protagonist|C
6272|Curseback|C
528|Curses|C
785|Curses|C
1658|Cute|C
224|Cute Children|C
1452|Cute Children|C
124|Cute Protagonist|C
1517|Cute Protagonist|C
125|Cute Story|C
6047|cuteflower|C
2149|cutegrapef|C
6019|Cutelittle|C
5793|cutelittle|C
2875|cutelovein|C
1522|CuteMaleLe|C
6121|Cutemeow-c|C
1731|CutePet|C
2760|cutepomelo|C
1972|cuteshadow|C
4978|cutewhite|C
3647|Cutthelone|C
4196|cutthrough|C
3294|Cyberpunk 2077|C
6074|cyclingwin|C
5429|Cyclospori|C
3456|cynicism|C
4194|D|D
5235|DaDaping|D
2432|Daddywants|D
2513|dagougou|D
4682|Dahuaisjea|D
2345|Dahunjun|D
6450|Dailytext|D
5579|Dailyupdat|D
4133|Dailyupdat|D
6680|Daji|D
5353|DaluoGod&a|D
4068|DamingComi|D
2162|DamingYong|D
380|Dancers|D
1955|dancetofig|D
3159|dandy|D
5143|DangeYihe|D
6792|Dangmei|D
1636|Danmachi|D
758|Danmei|D
5783|DanMing|D
417|Dao Companion|D
583|Dao Comprehension|D
6022|DaoguangEt|D
444|Daoism|D
6233|Daomen|D
2188|DaoyanShen|D
2238|DaqingXiao|D
5541|DaqinTombR|D
319|Dark|D
922|Dark Fantasy|D
574|DarkDeatho|D
5902|DarkFaust|D
4729|darkfriedg|D
1879|darknight|D
1816|darkpirate|D
1363|DarkPower|D
6628|darkwar|D
2423|Dashuaihen|D
2366|DatangDaqi|D
1938|DatangDaqi|D
1991|DatangErwu|D
3620|Datanggodo|D
2845|Datangpota|D
4143|Datangstyl|D
2003|Datangsupe|D
1145|Daughter|D
2084|daughterco|D
3893|Daughterof|D
6737|David|D
5665|Dawn&03|D
2545|Daybyday|D
5726|Dayefire|D
3480|Dayfestiva|D
3517|DayKunpeng|D
6208|DC Universe|D
835|DC Universe|D
5619|dcc98|D
5822|dd|D
723|Dead Protagonist|D
2318|deadfatfas|D
5359|deadfishda|D
6109|Deadwoodwa|D
6482|Dean|D
194|Death|D
64|Death of Loved Ones|D
4172|DeathofDae|D
515|Debts|D
1958|Decadeligh|D
5501|decayingro|D
3012|Decisive|D
6501|Decisivean|D
6594|decisiveba|D
4335|DecisiveMc|D
6373|Dedicatedt|D
6761|Dedication|D
6705|Deepaffect|D
1975|deepbluese|D
5257|deepdream|D
1371|DeepLTrans|D
5551|deepsea|D
3545|deepseadiv|D
4683|Dejarimi|D
247|Delinquents|D
640|Delusions|D
430|Demi-Humans|D
1230|Demon|D
218|Demon Lord|D
1124|Demon Slayer|D
6568|demonclan|D
2406|Demondomai|D
5175|DemonHunte|D
395|Demonic Cultivation Technique|D
2218|DemonInvas|D
2690|DemonKing|D
5847|DemonKingL|D
3560|DemonPower|D
219|Demons|D
1108|DemonsFami|D
65|Dense Protagonist|D
156|Depictions of Cruelty|D
1221|Depictions of Cruelty|D
303|Depression|D
6499|Derailed|D
3388|derivative|D
6493|Descent|D
6547|desert|D
3724|desertsalt|D
5596|desertspri|D
3385|Designer|D
3503|Desperate|D
5350|desperatec|D
2354|Desperatel|D
1531|DestinedLo|D
342|Destiny|D
6029|DestinyDra|D
4053|Destituteh|D
2309|Destroyerf|D
935|Detective|D
1347|Detective Conan|D
3223|Detectiver|D
180|Detectives|D
1143|Determined Protagonist|D
165|Determined Protagonist|D
3246|Develop|D
5280|Deviationo|D
5081|Devil|D
4956|devilcrayf|D
800|Devils|D
2293|Devilveget|D
4953|DevilWarri|D
24|Devoted Love Interests|D
1735|Devoted Love Interests|D
1776|DevotedCou|D
6330|Devouring|D
6338|Devourthes|D
6646|Diablo|D
5912|Diabloisno|D
4439|Dianhuo|D
5437|DianZhongD|D
3742|Didicat|D
5607|DidiDidi|D
136|Different Social Status|D
1367|differentw|D
4799|difficulty|D
2554|Diga|D
866|DiggingtoS|D
5582|Digigod|D
1767|Digimon|D
2021|digitalold|D
5370|DigJueJi|D
2598|digthreefe|D
2549|Dikabenka|D
2879|dimensiona|D
3181|Dining|D
1122|Dinosaurs|D
1103|Diplomacy|D
1492|Diplomats|D
3162|directdaug|D
1192|Director|D
4943|Dirge|D
4174|dirtyadmir|D
2739|dirtylittl|D
263|Disabilities|D
5045|disability|D
1693|DisabledPr|D
6464|disaster|D
1377|DiscipleLo|D
1318|DiscipleTr|D
3860|discordbir|D
504|Discrimination|D
634|Disfigurement|D
6271|Disguise|D
3245|Disguiseas|D
516|Dishonest Protagonist|D
5536|disillusio|D
1630|Disobedien|D
4225|distantsky|D
542|Distrustful Protagonist|D
535|Divination|D
678|Divination|D
984|Divine Protection|D
2863|DivineBook|D
5848|divineradi|D
1804|divinesign|D
6686|DivineSkil|D
44|Divorce|D
3199|DnD|D
2657|DoctorData|D
25|Doctors|D
1236|Doctors|D
3165|doctorstre|D
6668|Documentar|D
6082|Dodosaurus|D
5738|DoDumbbell|D
1749|Dog|D
3644|Dogcarp|D
2468|dogeggsold|D
1716|DoingBusin|D
2250|Dollsister|D
212|DollsPuppe|D
6298|DollyandDo|D
414|Domestic Affairs|D
6732|DomesticSt|D
6555|dominate|D
1503|Dominator|D
2912|Domineerin|D
6588|domineerin|D
4555|Domineerin|D
6296|Don&039|D
6056|don&039|D
5671|don&039|D
5490|don&039|D
5206|don&039|D
4901|don&039|D
4878|don&039|D
4457|Don&039|D
3880|don&039|D
3624|don&039|D
3496|don&039|D
2861|Don&039|D
2055|don&039|D
1968|don&039|D
5483|DongfangYu|D
4363|Dongfengbu|D
3941|DongmenSno|D
2566|Donotbecon|D
2573|Donotforge|D
3934|Donothinga|D
6049|Don’taske|D
5916|don’tgowi|D
4130|Doodle|D
1532|Doomdays|D
1080|Doomsday|D
6629|DoomsdayCr|D
2635|Doomsdaywa|D
3451|door|D
1010|doppelgang|D
2890|Doraemon|D
26|Doting Love Interests|D
1373|Doting Love Interests|D
177|Doting Older Siblings|D
178|Doting Parents|D
830|Doting Parents|D
1372|dotingfami|D
1396|dotinghusb|D
1664|DotingSibl|D
3267|Dotingwife|D
3341|doublebirt|D
5320|doublebirt|D
3313|Doublebusi|D
6199|Doublebusi|D
6355|DoubleClea|D
1185|DoubleLife|D
5950|doublepupp|D
1227|DoubleRebi|D
6526|doublerepa|D
1293|Doujin|D
4562|Doujinghos|D
5675|Doujinshi|D
6147|Doujipin|D
1038|DoulouDalu|D
326|Douluo Dalu|D
2917|Douluo Dalu|D
836|DouluoDolu|D
837|Doupo|D
826|DoupoBTTH|D
6228|Douro|D
3182|DouroConti|D
2992|DouroConti|D
2051|DouTuKing|D
2295|doyoueator|D
5216|doyouseemy|D
5595|Doyouunder|D
4007|Doyouwanta|D
2856|doyouwantc|D
5790|Dr.lifeadj|D
6509|Draft|D
1005|Dragon|D
1309|Dragon Ball|D
5649|Dragon Ball|D
5256|Dragon Ball|D
5183|Dragon Ball|D
2289|Dragon Ball|D
308|Dragon Riders|D
309|Dragon Slayers|D
5392|dragon&|D
2397|dragon-eat|D
2672|DragonandL|D
3919|DragonButt|D
5377|dragongodd|D
4459|DragonKing|D
6596|DragonKnig|D
5160|DragonLord|D
2005|DragonPala|D
3561|DragonPowe|D
310|Dragons|D
3992|DragonWarr|D
1934|dragracing|D
885|Drama|D
4494|drawing123|D
4552|drawTangpe|D
3575|Dream101|D
2812|dreamblizz|D
4597|dreambysta|D
2857|dreamcatch|D
3864|dreamglaze|D
2410|dreamintot|D
1797|dreamleave|D
4453|dreamnine|D
4120|dreamofmak|D
2153|Dreamofthe|D
494|Dreams|D
606|Dreams|D
5187|dreamstarr|D
5938|Dreamstrin|D
3981|dreamtogot|D
6744|DreamWorld|D
5265|DriedRadis|D
5134|driftingra|D
2514|DriftwoodD|D
4698|Drinkingam|D
5139|drinkmorew|D
3479|drinkupLan|D
3651|DrivingAdv|D
4591|DrivingHok|D
543|Drugs|D
506|Druids|D
4416|Drunkencat|D
2835|Drunklifed|D
4635|Drunkmeet|D
5113|DrunkMoonS|D
5165|Drunktime|D
4093|dryday|D
5095|DualCultiv|D
5850|Duaninksto|D
5494|DuckMantou|D
6570|duel|D
1071|DumbProtag|D
1354|dungeon|D
742|Dungeon Master|D
632|Dungeons|D
3994|DurianGras|D
4487|dustpatter|D
5267|DustRainMa|D
311|Dwarfs|D
1559|Dwarfs|D
783|Dwarves|D
3899|dwatermelo|D
5040|DXNTotoro|D
5191|DyeingBais|D
3436|Dynasty|D
618|Dystopia|D
275|e-Sports|E
5771|EagleRoadC|E
2|Early Romance|E
712|Earth Invasion|E
3564|eartwarmin|E
693|easternfan|E
998|EasternSet|E
434|Easy Going Life|E
1557|Easygoingp|E
3311|Eat|E
3850|Eatasteril|E
3704|Eatchicken|E
4964|eatfeet|E
3658|eatfishdon|E
1631|EatingBroa|E
4421|eatingmeat|E
5614|eatmoremea|E
5292|Eatsmallto|E
1596|Eccentricp|E
5085|Ecchi|E
505|Economics|E
738|EconomicsE|E
4771|Ecstasy|E
4277|edgecoatin|E
575|Editors|E
6451|Education|E
3356|Effort|E
2180|Eggpie|E
2792|Eggplantan|E
5451|Egoist|E
397|Eidetic Memory|E
3858|Eight-star|E
2925|Eighteence|E
4751|EighteenRa|E
4541|eighteight|E
6779|EighthRout|E
4609|eighthundr|E
4185|Eightswast|E
789|eincarnate|E
776|Elderly Protagonist|E
1769|electricia|E
2628|electricmo|E
4184|elegantlit|E
398|Elemental Magic|E
4350|Elemental Magic|E
1006|Elementali|E
1296|Elf|E
1905|Elfcold|E
1268|Elite|E
6562|Elixir|E
6579|Elvenscrip|E
354|Elves|E
5689|elvesandgh|E
3247|Elvish|E
6095|EmbraceofL|E
6507|Emotionally Weak Protagonist|E
381|Emotionally Weak Protagonist|E
3910|Emotionles|E
1513|Emperialpo|E
3411|emperor|E
2867|EmperorCha|E
3143|emperorstr|E
1937|EmperorYao|E
859|EmpireBuil|E
437|Empires|E
1202|Empires|E
3257|Empress|E
5047|empressfem|E
5275|emptydream|E
5900|emptyempty|E
4132|emptyhate|E
4440|emptymind|E
2407|emptymonol|E
4101|emptystard|E
6676|Encycloped|E
4883|EndlessSha|E
6061|Endlesswin|E
5177|EndoftheWo|E
2500|EndoftheWo|E
195|EnemiesBec|E
213|EnemiesBec|E
1771|enemiestol|E
3296|enemy|E
1623|EnemytoLov|E
1156|EnemytoLov|E
2674|engageinba|E
3283|Engagement|E
655|Engagement|E
697|Engineer|E
577|Enlightenment|E
6584|enterprise|E
1164|Entertaime|E
2460|Entertaini|E
228|Entertainm|E
874|Entertainm|E
6122|Entertainm|E
5327|Entertainm|E
5284|Entertainm|E
4637|entertainm|E
3083|Entertainm|E
3060|Entertainm|E
3037|Entertainm|E
3030|Entertainm|E
2961|Entertainm|E
2783|entertainm|E
2593|entertainm|E
1699|entertainm|E
879|Entertainm|E
5712|epicfantas|E
157|Episodic|E
6773|EQ|E
6643|equality|E
6380|era|E
5185|Ergouzi&am|E
5919|Erhuowon’|E
3948|ErieShaggy|E
4404|Eroticmeow|E
2776|Erwazi|E
3613|escapemarr|E
3183|Eschatolog|E
5340|Eschatolog|E
5315|Eschatolog|E
3074|Eschatolog|E
3002|Eschatolog|E
5889|Esper|E
6322|Espionage|E
5676|ESports|E
3477|Essencedre|E
6544|Eternal|E
6563|eternallif|E
5159|EternalLif|E
3767|eternallor|E
4320|eternalsta|E
2457|eternityor|E
6637|Ethereal|E
343|Eunuch|E
1830|EunuchJinr|E
457|European Ambience|E
3334|European Ambience|E
946|European Ambience|E
4188|Europeanem|E
4738|Europeansd|E
5768|evengod|E
3979|eveningdog|E
4594|Eveningwin|E
3523|evensuture|E
2708|Evergrande|E
2352|Evergrande|E
2678|everlastin|E
4589|EvernightB|E
2502|everydayfi|E
3097|everydayla|E
3079|everydayla|E
4199|Everyonewh|E
3761|Everyyear|E
808|Evil|E
333|Evil Gods|E
1058|Evil Gods|E
66|Evil Organizations|E
1386|Evil Organizations|E
382|Evil Protagonist|E
529|Evil Religions|E
1479|Evil-prota|E
1250|EvilCharac|E
3310|evildoer|E
5114|evilking|E
6502|evilspirit|E
5070|EvilSpirit|E
1712|EvilSprits|E
339|Evolution|E
5703|evolutiona|E
1534|Ex-girlfri|E
3851|excellentp|E
4425|ExcerptKin|E
6573|exchange|E
6277|Exchangeli|E
6348|Exercises|E
1752|exes|E
3847|Exhaustion|E
1036|Exhibitionism|E
468|Exorcism|E
1193|Exorcist|E
6293|ExoticLove|E
6500|Expectatio|E
1334|Experience|E
6609|experience|E
4945|Explodethe|E
6678|Explore|E
3137|Exposurefl|E
1603|Extraordin|E
4809|ExtremeAng|E
2240|Extremelyi|E
351|Eye Powers|E
1383|Eye Powers|E
6465|face|F
1620|Faceslap|F
914|FaceSlappi|F
2660|FahaiInvin|F
2251|Fahaiunder|F
3501|faintpenan|F
584|Fairies|F
1023|Fairy Tail|F
3546|Fairy Tail|F
2480|fairygirlf|F
6387|Fairyland|F
6389|FairyNavig|F
3619|Fairyrefer|F
1974|FairySword|F
5583|fairytailb|F
4137|FairyTailR|F
1824|Fairy丨Pin|F
3946|Fairy丨San|F
5656|Fairy丨Xiy|F
2555|fakegod|F
953|FaketoReal|F
596|Fallen Angels|F
524|Fallen Nobility|F
2108|Fallenleav|F
2767|FallenWing|F
1946|FallingRai|F
4145|fallinlove|F
2813|fallintoth|F
1304|Faloo|F
291|Familial Love|F
780|Familiars|F
1204|FamillialL|F
148|Family|F
459|Family Business|F
248|Family Conflict|F
854|FamilyBuil|F
1591|familylife|F
1676|FamilyLove|F
6746|Familymarr|F
3427|famous|F
627|Famous Parents|F
383|Famous Protagonist|F
1662|famouscoup|F
1918|Famousdete|F
6765|Famousthro|F
6358|Fan|F
183|Fan-fictio|F
6418|Fan-madede|F
710|Fanaticism|F
5935|fancywords|F
6145|Fanderivat|F
1194|Fanfic|F
184|Fanfiction|F
1545|FanFicton|F
2374|FangQingya|F
2272|FanJiu|F
2728|fanofstar|F
5009|fanqienove|F
4950|Fanqin|F
2265|FantaCola|F
5708|fantasticf|F
5570|Fantastico|F
391|Fantasy|F
362|Fantasy Creatures|F
4343|Fantasy Creatures|F
277|Fantasy World|F
6777|FantasyAdv|F
2496|Fantasybos|F
1753|Fantasyfut|F
3439|fantasyhis|F
5997|FantasyJi|F
532|FantasyMag|F
6136|fantasyspa|F
6118|Fantian36L|F
4607|faraway|F
3196|Farmer|F
3160|farmgate|F
229|Farming|F
1654|Farming|F
6660|Farmingnov|F
3067|farmingsys|F
1218|FarmingTex|F
5485|Farmingthr|F
6273|Fashionrin|F
67|Fast Cultivation|F
68|Fast Learner|F
1264|FastGrowth|F
3144|fastpaced|F
4348|fasttravel|F
3146|fastwear|F
5330|fastwear1V|F
3063|fastwear1V|F
3028|fastwearCo|F
5305|fastwearIn|F
1466|FastWearin|F
5310|fastwearNo|F
3081|fastwearPr|F
2960|fastwearRe|F
3061|fastwearst|F
5346|fastwearsw|F
358|Fat Protagonist|F
359|Fat to Fit|F
4099|fatcatunde|F
5441|Fatcatwhow|F
2594|FatDiddy|F
5767|FatDragonJ|F
5287|Fate90degr|F
272|Fated Lovers|F
4488|Fated Lovers|F
1404|fatedxd|F
6270|FatefulEnc|F
1585|FateSeries|F
3419|Fatestayni|F
1146|Father|F
4328|FatHouseDu|F
5647|Fathouselo|F
6489|Fatman|F
2060|fatmanoffa|F
4556|Fatmeowdoe|F
4370|fatorange|F
2707|Faucet|F
2110|Favoritebl|F
6100|Favoriteco|F
2759|Favoriteco|F
3814|favoritegr|F
3915|favoritepo|F
3867|Favoriteup|F
6512|Fearless Protagonist|F
639|Fearless Protagonist|F
3513|featherand|F
4236|federalhea|F
1947|FeiLuEdiso|F
3686|FeitianOld|F
629|Fellatio|F
557|Female Master|F
18|Female Protagonist|F
1226|Female Protagonist|F
2913|Female Protagonist|F
734|Female to Male|F
6769|Femaledoct|F
4012|FemaleEmpe|F
1586|FemaleFigh|F
3248|femalehono|F
986|FemaleLead|F
3121|femalematc|F
1391|FemaleMC|F
4347|FemalePart|F
1458|FemalePres|F
5745|femaleprim|F
6520|femalesold|F
1493|FemaleSpie|F
1178|FemalesPro|F
581|Feng Shui|F
3585|FengLingzo|F
5199|FenglinYey|F
2425|Fengqing|F
6691|FengShui师|F
5273|FengTingyu|F
4543|FengyueXun|F
5205|Fengzilike|F
2077|FengziXiao|F
5810|Fenwhoeats|F
1928|FerrariEnz|F
5094|Fetish|F
6210|ff|F
5450|Fiction|F
6784|FictionalD|F
4046|fieldowner|F
2128|fierce|F
5212|Fierceadve|F
3273|fiercewife|F
2808|Fifi&03|F
2454|FifthEmper|F
5931|FifthQingl|F
3281|Fightagain|F
6394|fighting|F
2450|FightingCo|F
6164|Fightingfo|F
5687|Fightingpi|F
6324|Fightingth|F
6557|file|F
6672|Filigree|F
1682|Filipino|F
1681|FilipinoNo|F
6749|Filmandtel|F
3368|Filmempero|F
2895|Finance|F
5424|Fineartisl|F
3638|finepoint|F
3877|fingertips|F
166|Firearms|F
1407|fireborn|F
4650|firefire|F
2040|Fireinthes|F
2602|fireonfire|F
1810|Firethief|F
2384|FireWinged|F
4902|FireXinxin|F
207|First Love|F
882|First-time Intercourse|F
192|First-time Intercourse|F
3298|firstaid|F
4662|firstfragr|F
2535|firstgreen|F
1989|firstperso|F
2481|fishandraf|F
3530|fishdragon|F
2869|fisheatpan|F
2070|fishfishda|F
2814|Fishheadis|F
2753|fishinflam|F
1131|Fishing|F
4972|fishinginf|F
4117|Fishingmak|F
2779|fishswimmi|F
5722|five-color|F
5702|FiveDynast|F
3491|flamboyant|F
1835|flamingfla|F
135|Flashbacks|F
4441|FlashBonda|F
5405|flashhusky|F
745|Fleet Battles|F
3616|flirtatiou|F
5036|flirtyclou|F
191|Fllatio|F
3987|Floatingcl|F
4916|floatingdu|F
2550|Floatingli|F
6306|Floatingon|F
4800|floatingse|F
3220|flood|F
3045|floodRelax|F
3369|Flourishin|F
3967|Flower&|F
4180|FlowerBlos|F
3177|flowercare|F
3077|flowercare|F
2997|flowercare|F
4400|flowerdust|F
6171|Flowerprot|F
5952|Flowersblo|F
6282|Flowerseas|F
2805|flowersoft|F
5258|Flowingclo|F
4933|Flowingclo|F
5784|flyburning|F
2547|flyingcow|F
4458|FlyingDrag|F
2146|flyingfish|F
4019|Flyinggras|F
2522|flyinglitt|F
2301|FlyingLuTi|F
4710|Flyingmeat|F
3914|flyingnood|F
2719|flyingshar|F
5304|Flyingsnow|F
2364|flyingsqui|F
2862|Flyingwhit|F
2615|flyinthelo|F
4124|flytothemo|F
3795|FocusSpeci|F
4204|Foggy|F
4732|FogLan|F
4628|foldedkite|F
5668|Foldoffthi|F
6236|Folklegend|F
623|Folklore|F
3364|folksuspen|F
2091|Followthew|F
5877|Fomalhaut7|F
1317|Food Wars!|F
814|Food Wars!|F
3414|foodie|F
987|FoodShopke|F
4871|fool|F
352|Football|F
6515|force|F
110|Forced into a Relationship|F
317|Forced Living Arrangements|F
111|Forced Marriage|F
5503|Forcedtomo|F
6399|Foreigncou|F
6222|ForeignHis|F
3261|foreignwei|F
3716|Forensic|F
2134|forest|F
4291|forestinth|F
384|Forgetful Protagonist|F
2211|Forgiveyou|F
5476|forgottoun|F
4192|Formation|F
1346|Formations|F
478|Former Hero|F
2817|formworksk|F
5362|fornoreaso|F
6733|Fortunetel|F
6065|Fortyacres|F
2451|Fourkeys|F
5088|Foursome|F
1276|FourthDisa|F
3433|Fox Spirits|F
256|Fox Spirits|F
5554|foxcontrol|F
6721|FoxDemon|F
5533|foxdemonpr|F
2377|FoxdemonXi|F
6754|FoxFairy|F
3809|Foxhimself|F
1827|foxlisteni|F
6183|fqloo|F
4696|Fragmentof|F
4070|fragmentso|F
1496|France|F
5933|frenchcoun|F
4417|frenzyflow|F
5864|Freshparad|F
932|Friction|F
1885|Friday|F
3739|fried|F
4781|FriedJunhu|F
4514|Friedsquid|F
6415|friend|F
737|Friends Become Enemies|F
421|Friendship|F
5837|Fromnowon|F
4063|Fromthepup|F
5489|Frostandsn|F
5867|FrostZhong|F
4215|Frozencorn|F
3676|FuHejun|F
69|Fujoshi|F
3339|Fukujin|F
6323|Full-timeM|F
3841|Fullcolor|F
3404|fullflow|F
6237|Fulllevelf|F
2173|fullmeal|F
3853|Fullyarmed|F
6275|Fumino|F
6759|Fun|F
6620|Fund|F
4897|FungMingHe|F
3138|Funny|F
6198|Funnycomme|F
2336|furioussna|F
3607|Furutake|F
5365|fusion|F
4319|FusoFantas|F
193|Futanari|F
1698|Future|F
355|FutureCivi|F
1252|FutureCivi|F
5049|futuredyst|F
6139|Futureover|F
2909|futureworl|F
3056|futureworl|F
2989|futureworl|F
126|Futuristic Setting|F
1500|Futuristic Setting|F
4859|Fuyuan|F
5445|gacha|G
1917|Galacticos|G
2245|Galaxyboy|G
1266|GalaxyWars|G
1109|Galge|G
6214|Gallery|G
4284|GambitPara|G
661|Gambling|G
3729|gamblingst|G
822|Game|G
70|Game Elements|G
868|Game Elements|G
1627|Game Elements|G
3422|Game of Thrones|G
392|Game Ranking System|G
3153|gamealien|G
2978|gamealienO|G
3006|gamealienp|G
2966|gamealienV|G
6154|Gamealienw|G
6244|GameArticl|G
3763|GameLit|G
1449|GameOnline|G
3430|gameplayer|G
3154|Gameproduc|G
1246|GameRangki|G
170|Gamers|G
6410|Games|G
1220|gameworld|G
1133|Gaming|G
385|GamingE-Sp|G
321|Gangs|G
6701|Gangs|G
3226|Gangster|G
798|Gangsters|G
4148|GanYu&0|G
5673|Gao Wu|G
2666|GaoYuanyao|G
6461|GaoZhi|G
214|Gate to Another World|G
3110|Gatevalve|G
1590|Geass|G
3408|Geeky|G
1012|GenderBend|G
1632|Genderless Protagonist|G
609|Genderless Protagonist|G
6284|GenderTran|G
3315|gene|G
6730|Geneevolut|G
1315|GeneModifi|G
3349|Generals|G
233|Generals|G
2773|GeneralXie|G
312|Genetic Modifications|G
3340|geneticwar|G
215|Genies|G
216|Genius Protagonist|G
1421|Genius Protagonist|G
3129|geniusflow|G
3016|geniusflow|G
6572|geniusstre|G
1321|Genshin Impact|G
1510|Genshin Impact|G
1750|GentleLove|G
1986|gentleman|G
5236|GentlemanI|G
4646|GentlemanM|G
1722|GentleProt|G
4909|Gentlygath|G
4034|Georgia|G
3896|germanicsn|G
4749|getonit!|G
1717|GetRich|G
6072|Getrichbys|G
6126|Getupearly|G
2677|Ghostexter|G
6494|GhostHunti|G
6724|GhostPath|G
158|Ghosts|G
1099|Ghosts|G
2402|Ghostsinre|G
6655|GhostSword|G
6710|Ghosttalen|G
3151|Giant|G
2840|giantpanda|G
5090|Gilf|G
3380|GingerLemo|G
6367|girl|G
1198|Girl&03|G
1191|Girl&03|G
4697|girlfallsi|G
1149|girlfriend|G
5951|Girlsareet|G
6251|GirlsComic|G
2058|giveyoutim|G
981|Gladiators|G
703|Glasses-we|G
624|Glasses-we|G
4419|glasseswei|G
4281|glasssauce|G
6102|glassysky|G
2329|GLL|G
4545|GlobalTop1|G
4888|gluttoneat|G
1942|Go|G
2659|goallist|G
616|Goblins|G
1297|God|G
298|God Protagonist|G
4573|God&039|G
2171|God&039|G
668|God-human Relationship|G
3304|God-levelf|G
1508|GodandDevi|G
4241|Godcat|G
2378|goddessbos|G
278|Goddesses|G
1575|Goddesses|G
2414|Goddidnotg|G
6354|GodKing|G
1443|GodLikeMC|G
356|Godly Powers|G
1582|Godly Powers|G
960|GodlyProta|G
3626|Godofcreat|G
1908|godofduel|G
1996|GodofForti|G
4519|godofrainy|G
6564|GodofSlaug|G
6437|GodofWar|G
2324|Godofwings|G
234|Gods|G
2589|godsaltedf|G
6434|GodsandDem|G
6716|GodsList|G
1710|Godzilla|G
2634|Golden|G
963|GoldenFing|G
2751|goldenfore|G
4678|GoldenMang|G
5617|goldenswor|G
5815|goldenthom|G
1941|goldfinger|G
3031|Goldfinger|G
2938|Goldfinger|G
4274|goldrush|G
778|Golems|G
5775|GoneDouble|G
2078|GoneStrawb|G
3254|Gongdou|G
5334|Gongdou1V1|G
3078|Gongdouswe|G
5690|GongdouZha|G
3894|gongregret|G
5465|Goo!Justki|G
2651|good-natur|G
4212|goodbyeex|G
1870|goodpotdre|G
4410|Goodsir|G
5470|goodstar|G
4003|googoogoog|G
2853|Gooifyouca|G
5296|goose|G
94|Gore|G
1861|goslowbro|G
2053|gossip|G
2090|Gotaki|G
3550|Gotoschool|G
5247|gotta|G
4222|Gouor|G
1551|Gourmet|G
4571|GouTaoist|G
1616|Government|G
4134|GovernorWh|G
6007|Graceunder|G
6408|grade|G
1799|GradeXNUMX|G
4994|gradually|G
6398|Grandmaste|G
3180|Grandpa|G
4659|Granvillec|G
5202|GrassCrick|G
3128|Grassroots|G
1016|Grave Keepers|G
1430|gravityfal|G
4827|Grayborn|G
5899|greatbriti|G
2317|GreatCeles|G
5401|GreatCod|G
4147|GreatDesol|G
4256|GreatDrago|G
3554|Greatgod|G
4263|GreatQinIm|G
4000|GreatQinvi|G
2037|GreatSage|G
4186|greedydrin|G
1217|GreedyProt|G
3577|GreenCong|G
4810|greenfruit|G
4288|greengrass|G
3337|Greenplum|G
1777|greentea|G
5505|greenteaL|G
5147|GrilledPac|G
3957|GrilledPir|G
787|Grimdark|G
3459|grimReaper|G
4893|GrimReaper|G
544|Grinding|G
3188|Group|G
1272|GroupChat|G
6151|Groupfavor|G
2914|GroupPet|G
3591|groupwear|G
6137|growingup|G
1486|Growth|G
6333|grudgesand|G
3947|Grumpyoldm|G
5942|grumpyoran|G
1477|Grupchat|G
4406|GuaguaSoar|G
264|Guardian Relationship|G
4250|GudaoZhous|G
4840|Gugu|G
4913|gugugugu|G
631|Guilds|G
2581|GuiltyScis|G
5418|Guluton|G
1741|Gundam|G
95|Gunfighters|G
5294|GuodianAna|G
3272|Guoshu|G
5711|Guoshuflow|G
1858|GuShaoxia|G
2737|H11H|H
6566|habit|H
3688|Hachime|H
367|Hackers|H
957|Hackers|H
4610|Hahariding|H
1768|Haikyuu|H
5988|Hailuojun|H
2398|HakoniwaSe|H
265|Half-human Protagonist|H
3539|halfafrog|H
2618|halfanoran|H
5394|HalfCityDe|H
3643|HalfJiangS|H
4525|halfmoonem|H
4961|halfnights|H
5238|halfsmoke|H
2476|halfstepge|H
5555|halfstring|H
811|Halo|H
4854|HamabeMiwa|H
2689|Haminstant|H
699|Handjob|H
3656|HandjobBet|H
11|Handsome Male Lead|H
3566|Handsome Male Lead|H
6638|Handsome Male Lead|H
1656|Handsome Male Lead|H
4329|handsomeat|H
6023|handsomebl|H
2789|Handsomegu|H
5096|HandsomeMC|H
6497|Handsomeme|H
2607|handsomeon|H
1195|HandsomePr|H
2362|handtearin|H
5388|HanlinBrok|H
5173|HansChrist|H
4318|HanXiaoshe|H
2356|HaotianExt|H
3379|HaoyuYingx|H
6521|happiness|H
1157|Happy|H
2177|HappyBeanl|H
4886|happydrago|H
833|HappyEndin|H
3094|happyenemy|H
4522|Happyfirst|H
2825|HappyFlow|H
3664|happylittl|H
3687|happylutho|H
127|Hard-Working Protagonist|H
3424|HardSci-fi|H
6292|HardScienc|H
4428|hardtofind|H
4857|Hardworkin|H
1173|Hardworkin|H
37|Harem-seeking Protagonist|H
324|Harem-seeking Protagonist|H
2521|Haremismta|H
1084|HaremSeeki|H
6703|harmonious|H
5635|Harpertime|H
5435|harpyfrog|H
237|Harry Potter|H
1427|Harry Potter|H
625|Harsh Training|H
5941|HarukoHaru|H
2100|Hashihime|H
112|Hated Protagonist|H
4270|haveagoody|H
4967|havealongm|H
6128|Haveasofts|H
4095|haveryconf|H
2330|Hawkeye|H
3961|hazelneck|H
3152|HE|H
3707|Head|H
5911|headedsalt|H
4831|Headmaster|H
4642|HeadofShil|H
566|Healers|H
1474|Healing|H
6657|Health|H
2326|Healthewor|H
6458|healthy|H
2619|heartandey|H
2684|HeartHunte|H
106|Heartwarming|H
4283|Heartwarming|H
582|Heaven|H
2526|heavenclea|H
128|Heavenly Tribulation|H
3481|HeavenlyKi|H
2544|heavensong|H
5805|HefanAnzi|H
2904|Hegemony|H
6011|Hehehehehe|H
5276|HeHuaninth|H
4268|HeiTongWuG|H
651|Hell|H
612|Helpful Protagonist|H
4622|helpmeup|H
4146|HengdianXi|H
978|Hentai|H
779|Herbalist|H
3623|hereIcome|H
5342|HERelaxeds|H
6518|hermit|H
536|Heroes|H
784|Heroes|H
1961|Heroesofth|H
1778|heroine|H
3161|heroinecut|H
4126|Hesitatean|H
969|Heterochromia|H
3009|HEwearbook|H
5855|hewon&0|H
4460|Hexue|H
5413|HeXueguan|H
2094|hey|H
5523|HeYeTonggu|H
4920|HeyMajesty|H
1995|hi|H
4596|hibernatin|H
4868|HidakaDanc|H
259|Hidden Abilities|H
5411|hiddenbook|H
1483|HiddenBoss|H
982|HiddenGem|H
921|HiddenIden|H
1216|HiddenIden|H
3258|hiddenmarr|H
5338|hiddenmarr|H
1107|HiddenTrue|H
1210|hiddenvest|H
1135|HiddenYrue|H
4928|Hidethepen|H
479|HidingAbil|H
200|HidingTrue|H
117|HidingTrue|H
1086|HidingTrue|H
958|HidingTrue|H
6426|High-ranki|H
3429|Highcold|H
1666|HighFantas|H
1428|highiq|H
1039|Highschool DxD|H
1159|Highschool DxD|H
2104|Higu|H
4158|Hikari|H
5716|HiKeli|H
3239|Hikusei|H
4057|Hiroyuki|H
4925|hishy|H
2430|HisMajesty|H
4374|HisnameisJ|H
4265|HisRoyalHi|H
5709|Historical|H
824|Historical|H
6742|Historical|H
6281|Historical|H
860|History|H
5885|Historyoft|H
2927|hitten|H
4385|hitthestre|H
376|Hndjob|H
1608|Hogwarts|H
845|Hokage|H
5758|HoldingaMe|H
5756|Holdthemom|H
1196|Hollywood|H
2017|holyangel|H
5184|HolyFather|H
3964|HolyFireDT|H
1826|HolyKingRa|H
3891|holymonk|H
6062|HolyWaterP|H
2369|HomeAttrib|H
3913|homelessma|H
648|Honest Protagonist|H
2622|HonestandR|H
4144|honestdogg|H
3470|honestking|H
4387|HongchenJi|H
2597|HongfeiQin|H
5779|HongHuangB|H
2516|HonghuangN|H
4496|HonghuangS|H
2217|Honghuangs|H
5286|HongHuangz|H
4018|HongKongFi|H
6483|Hongmeng|H
1783|HongmengSh|H
1886|HongTang|H
5936|Hongxuetyp|H
1375|Honkai Impact 3|H
4171|Honkai1999|H
3586|HonkaiMess|H
6506|hope|H
5482|hopeful|H
4691|hornreverb|H
6160|Horor|H
818|horror|H
2394|horrorgod|H
4873|horsehorse|H
5828|HoshinoSor|H
636|Hospital|H
300|Hot-blooded Protagonist|H
3013|HotBlood|H
906|Hotels|H
4821|Hotpepper|H
2721|hotpot|H
6649|hotspot|H
3170|housefight|H
5336|housefight|H
5326|housefight|H
3049|housefight|H
5132|housegirl|H
5545|housekeepe|H
2412|houseprope|H
5389|howcomfort|H
2312|howlingpig|H
2770|howlingwin|H
5444|Huahuababy|H
4988|HuaihaiChi|H
2061|HuanHuanHu|H
6006|HuaNiaoFen|H
4042|HuaXiaowas|H
4704|hugTA&0|H
2236|Huijingund|H
1997|HuiMochou|H
4382|HuiXiaCong|H
6539|Hukou|H
4653|human|H
413|Human Experimentation|H
1392|Human Experimentation|H
490|Human Weapon|H
159|Human-Nonhuman Relationship|H
6288|Humanities|H
6231|Humanity|H
6704|Humanityan|H
5803|humannatur|H
129|Humanoid Protagonist|H
3277|Humbleboy|H
5093|Humiliatio|H
2221|humla|H
6653|humor|H
4064|hundredhou|H
3562|hunter|H
1338|Hunter x Hunter|H
1881|hunterkill|H
4245|hunterleav|H
531|Hunters|H
2921|Hunter×Hu|H
5148|HunyuanDal|H
6567|HuoQubing|H
3791|Huoshulour|H
3771|HuoxiangZh|H
5914|Hurry|H
6476|hurt|H
6433|Husband|H
2386|HuTiandi|H
5602|HuYuan&|H
1062|HxH|H
5747|HyogoNorth|H
1927|hyperknigh|H
377|Hypnotism|H
4249|I&039ll|I
4949|I&039ma|I
3657|i&039ma|I
2191|I&039ma|I
3674|I&039mj|I
5186|I&039mn|I
4484|I&039mn|I
2351|I&039mo|I
4500|I&039mr|I
4026|I&039ms|I
3655|I&039ms|I
4529|I&039mX|I
3519|ialmostbel|I
3963|iamabigsal|I
4639|Iamamelanc|I
2321|Iamapirate|I
4630|Iamareader|I
2304|Iamarealdi|I
2744|IamAsi|I
1930|iamatravel|I
2314|Iamfifth|I
2438|IamGuanxi|I
2443|Iamhell|I
2296|IamHisMaje|I
2009|Iamnotaloc|I
5774|Iamnottheo|I
2269|Iamolderth|I
2695|Iamoldwolf|I
2765|Iamthemurd|I
1890|Iamtheseak|I
2650|Iamtheseco|I
2596|Iamtwenty-|I
6301|Iamwilling|I
2931|Iateeightc|I
3813|IbukiGourd|I
2580|Ibuprofen|I
2036|icalledthe|I
4456|Ican&03|I
4088|Icanreally|I
6414|iceberg|I
4412|IceCreamAs|I
4197|iceddaught|I
2826|IcedDurian|I
4575|icesweet|I
1979|icewalk|I
3578|Icomefromt|I
6488|ideal|I
344|Identity Crisis|I
3278|ideologica|I
5777|Idiotdeado|I
4788|idlerscome|I
1301|Idol|I
4661|Idon&03|I
4031|Idon&03|I
2195|idon&03|I
6034|Idon’tkno|I
1839|idropbaby|I
2609|ieatgrass|I
4624|ieatguava|I
4248|IfIdon&|I
6068|ifthewindi|I
2118|Ifyoucango|I
5201|Igotit!|I
4140|Ihaveeight|I
4407|ihaveseven|I
2774|ihavethere|I
1906|Ijustwantt|I
3495|Ilikedried|I
2010|Iliveupsta|I
1714|Illigitima|I
1786|Ilo|I
3508|Iloveboile|I
6041|ilovegrape|I
4774|ilovewatch|I
2704|ilovewoo|I
4770|immeasurab|I
1077|Immortal|I
2658|ImmortalBi|I
3428|ImmortalEm|I
2781|ImmortalMa|I
235|Immortals|I
238|Imperial Harem|I
5035|ImperialCa|I
5706|Imperialco|I
6504|ImperialCo|I
1473|imperialco|I
6117|ImperialCu|I
3276|Imperialex|I
1088|ImperialFa|I
5056|Imposter|I
6206|ImprovedTr|I
5393|inactionin|I
5548|Incarnatio|I
179|Incest|I
5115|inchshadow|I
4169|Inclassroo|I
3970|Inclined|I
1019|Incubus|I
568|Indecisive Protagonist|I
4271|Indestruct|I
6462|indifferen|I
6630|indigenous|I
1687|Indonesia|I
1686|IndonesiaN|I
4033|indulgemyd|I
641|Industrialization|I
3565|Industrialization|I
1269|Industry|I
6131|Industryel|I
5053|industryel|I
2949|industryHo|I
4206|Inexplicab|I
3158|infatuatio|I
431|Inferiority Complex|I
2067|Infernalco|I
1368|infinite|I
2190|InfiniteBu|I
1292|InfiniteFl|I
5825|infinitega|I
2027|Infiniteme|I
2531|infinitesu|I
1374|infrastrac|I
1384|Infrastruc|I
6240|Infrastruc|I
3431|Infrastruc|I
4687|Ingeniousg|I
4699|Inherenten|I
426|Inheritance|I
2804|Ink|I
4586|Ink-dyedIm|I
4583|inkdirty|I
3206|inlove|I
3666|Inlovewith|I
1638|InnerVoice|I
3949|innocentmo|I
744|Inscriptions|I
313|Insects|I
4856|Insectword|I
2816|insitu|I
3869|insomniaun|I
3253|Inspiratio|I
5996|Instantnoo|I
5917|instantnoo|I
4705|instantsta|I
5447|Instructor|I
6645|intelligen|I
1029|intenseflu|I
2801|Intercept0|I
1988|Intercept0|I
1745|Interconnected Storylines|I
27|Interdimensional Travel|I
927|Interestel|I
6711|interestin|I
5713|interpenet|I
6152|interracia|I
5684|Interracia|I
903|Interstell|I
2967|interstell|I
4286|inthecloud|I
4969|inthenameo|I
680|Introverted Protagonist|I
4937|InukaiOmor|I
1125|Inuyasha|I
6635|invention|I
496|Investigations|I
1169|Investigations|I
6538|investment|I
3106|Invincible|I
5449|Invincible|I
5244|Invincible|I
3680|Invincible|I
3029|Invincible|I
2964|Invincible|I
2942|Invincible|I
1956|Invincible|I
1887|Invincible|I
1875|Invincible|I
1812|Invincible|I
6217|Invisibility|I
5740|InvolveNo.|I
3098|IQOnline|I
6037|Ireallydon|I
5646|Ireallywan|I
4761|Ireallywan|I
6612|IronBlood|I
3719|ironfistri|I
2923|IronMaiden|I
6640|ironMan|I
2339|ironpillar|I
2665|IronThanos|I
4211|iscoding|I
850|Isekai|I
4599|Isellflowe|I
5481|IsitatLoli|I
2063|isitnecess|I
1671|IsItWrongt|I
2102|Isuckbrown|I
2490|IsumiLily|I
5894|It&039s|I
5195|it&039s|I
4252|It&039s|I
3932|It&039s|I
2179|It&039s|I
5672|Itbecameaf|I
6042|Itissaidth|I
5397|Itissaidth|I
2113|Itsdaybrea|I
4932|Itwillbead|I
5994|It’sAmoyo|I
5903|It’syouwh|I
4834|Iunotbad|I
2463|iwantmoney|I
3950|IwantSiste|I
2866|Iwanttobea|I
2523|Iwanttobeo|I
2811|iwanttoeat|I
6076|Iwanttogot|I
2636|iwanttogot|I
6055|Iwanttohit|I
3474|Iwanttolie|I
5513|iwanttosee|I
4667|Iwanttosee|I
4364|Iwanttotak|I
5813|Iwillbecom|I
2114|Iwishyouat|I
4152|Izanagi233|I
71|Jack of All Trades|J
5382|Jackdaw|J
2891|JackieChan|J
2334|jadeeveryy|J
3463|Jaderabbit|J
3806|JaneShu|J
1793|JangSeok-g|J
3953|januarygod|J
1342|Japan|J
843|Japanese|J
907|JapIdols|J
6549|Japs|J
5564|JasperKnif|J
2679|Jazz|J
258|Jealousy|J
5862|jediescape|J
2872|jellyjelly|J
3209|JianBao|J
4785|JiangCheng|J
1258|Jianghu|J
5697|Jianghugri|J
603|Jiangshi|J
4841|JiangWu|J
5034|JiangYu|J
2387|Jianjiamix|J
4173|Jiaqi|J
6170|JiDaoliu|J
6176|Jin|J
2763|JinglongTa|J
5879|JingShenTi|J
4570|JinguNoFun|J
3499|Jinwan1|J
3400|JinYiwei|J
5846|Jiulu丶|J
2170|Jiutianyu|J
4166|Jiuxiao|J
3737|JiuYuan|J
4989|JixingGaoz|J
6004|JiYipao|J
4205|JKing|J
4065|JOAmbulanc|J
5516|JoanHuang|J
2641|John117|J
2883|JoJo&03|J
1126|JojoBizarr|J
1954|JOJOWE|J
2882|JoJo’s Bizarre Adventure|J
886|Josei|J
1326|Journey to the West|J
6468|joy|J
2013|joydrummer|J
1127|Jujutsu Kaisen|J
1811|Juliet|J
5831|July&03|J
4313|JulyBrewma|J
2791|JunCaiXing|J
5770|Jundrunkdr|J
5608|Jung|J
2176|JuniorSist|J
4605|JunRuoxu|J
4422|JunRuyu|J
3988|justapiece|J
5245|justdrunk|J
4879|justplay|J
4685|justsaydon|J
2795|justshout|J
5808|jzkyushu|J
1102|K-popIdols|K
2035|Kafkajumpi|K
5387|Kahn|K
3886|Kailandros|K
4666|KakamieCro|K
846|Kakashi|K
4023|KakashiTen|K
6529|Kangxi|K
4261|KanohiroSa|K
999|Karma|K
4604|Karmadance|K
5012|Katena|K
4258|Kaying|K
3538|Kazamahyac|K
4195|keel|K
4254|keepitsimp|K
1001|Kendo|K
5558|KennelSaku|K
4795|KensenShin|K
3785|keyboardki|K
3958|keykey|K
2458|keytocome|K
509|Kidnappings|K
5587|KiharaKaqu|K
3126|killdecisi|K
3608|Killer|K
6086|killerwhal|K
5761|killpigeon|K
6723|KilltheJap|K
2196|Killthewor|K
3879|Kim&039|K
6067|KimuraShit|K
131|Kind Love Interests|K
1754|Kindergart|K
3726|Kindergart|K
3405|Kindness|K
1462|KindomBuil|K
1464|KindProtag|K
1901|King|K
2391|KingAsura|K
1629|Kingdom|K
340|Kingdom Building|K
871|Kingdom-bu|K
181|Kingdoms|K
533|KingdomsKn|K
2629|KingKonggo|K
3528|KingLingyu|K
6764|Kinglyway|K
2592|kingofdeat|K
1823|KingofDest|K
5111|kingoffoot|K
2437|KingofMons|K
3268|KingofSold|K
2185|kingpirate|K
2518|Kiritani|K
5223|kittenrun|K
2796|Kneelingan|K
2305|Kneelingth|K
2001|KnifePromi|K
4231|knightcomm|K
5707|knightflow|K
5580|knightinar|K
4497|knightmeow|K
900|Knights|K
208|Knights|K
613|KnightsLev|K
3621|knightupgr|K
5566|Knockingca|K
4461|knowfate|K
3815|KnowKingAl|K
6548|Knowledge|K
2478|Knowtheric|K
1578|Koi|K
3757|KoiKing|K
2216|Kojin|K
4058|Konohasalt|K
2532|KonohaVoll|K
6688|Korea|K
1674|Korean|K
1310|KoreanNove|K
6487|KoreanWar|K
5531|KotomineSa|K
908|KpopIdols|K
5538|Kuchikiwha|K
5149|KunHao|K
2008|KurongTemp|K
4170|Kutiaoren|K
708|Kuudere|K
2043|KwunTong|K
3807|KyokoKurot|K
5812|Kyokowassi|K
2527|laborhonor|L
160|Lack of Common Sense|L
2262|lackofboat|L
2099|LacquerNig|L
3403|lady|L
3821|LaidBack|L
3482|LaiXiaomin|L
5839|LambSoupwi|L
2310|LameHaoisa|L
133|Language Barrier|L
2441|langyalist|L
4992|LangyaPavi|L
2076|LaoLaoXu|L
3976|LaoWang|L
4715|Lappy|L
4717|LargeBoard|L
5137|lasercatbo|L
6395|Lastday|L
4072|lastnight|L
3595|lastwear|L
249|Late Romance|L
6503|LateHanDyn|L
6608|latency|L
5664|latenightf|L
5780|laughandcr|L
3954|laughingor|L
2201|laurel|L
5403|LawofNineG|L
3458|Lawyers|L
548|Lawyers|L
3192|layoutflow|L
2982|layoutflow|L
441|Lazy Protagonist|L
3555|Lazy Protagonist|L
4399|lazyandcru|L
4469|lazyangel|L
4062|lazycaramb|L
4720|lazycatsch|L
5958|LazycatZ|L
2120|lazydevil|L
3525|Lazyintoab|L
4016|LazyYang|L
375|Leadership|L
3357|leadthemai|L
3801|leadwall|L
4590|LeafofTian|L
849|League of Legends|L
5507|Leaningont|L
4312|Leaningont|L
3542|leaningont|L
2347|Leapeveryd|L
5409|Leaves|L
5467|leavesfall|L
5725|Leavingaga|L
4282|Leavingthe|L
3746|leftandrig|L
3612|Leftgirl|L
5457|leftpigeon|L
6513|LegendaryL|L
701|Legends|L
607|Legends|L
4190|leggod|L
6533|legitimate|L
3670|LeiHuofeng|L
1933|LeiJiedoes|L
2426|Leisurelys|L
3372|LeiXunqing|L
4331|LeJiangli|L
5881|Lemonade|L
2285|lemonandsi|L
4178|lemoneatar|L
3870|Lemonfruit|L
3875|lemonlemon|L
2837|lendmefive|L
4549|LengquanAt|L
1035|leonine|L
3918|lessmeatmo|L
1842|lesstime|L
5845|Let&039|L
4898|Let&039|L
3692|Letmetelly|L
4243|Levatin|L
201|Level System|L
4156|levelthree|L
5055|Levelup|L
3883|LeYang|L
994|LGBTQA|L
3888|LiangFeifa|L
4794|Lianhai&am|L
4767|LianHongyu|L
4323|LianshanGu|L
3445|LiaoZhai|L
1165|Liar|L
4779|LiBaiisnot|L
773|Library|L
6439|lie|L
5547|Liedown|L
6402|Life Script|L
1721|Life Script|L
5301|lifealive2|L
3568|lifeanddea|L
5023|lifeextrac|L
4975|Lifeisthre|L
6094|Lifelongfa|L
3509|lifestillh|L
5678|Lifestyle|L
3526|lightandsh|L
4503|lightfluff|L
2163|Lightnings|L
1680|LightNovel|L
1405|lightnovel|L
3492|lightofday|L
3682|lightsaber|L
4299|lightsail|L
2756|LiJunhao|L
1907|LikeaDrago|L
1902|LikeaDrago|L
2582|LikeMeiAox|L
4307|lilac|L
2642|Lillie|L
5440|Lily&03|L
5150|LilyNo.XNU|L
6106|LiMengxi|L
470|Limited Lifespan|L
794|LimitlessF|L
2280|LiMumu|L
2730|LinBei|L
5528|lindenone|L
2745|Lindentree|L
3518|LingbiWhit|L
3332|Lingen|L
4384|LingHanyi|L
5291|LingLingSa|L
4663|LingLuoBai|L
5785|LingofGemi|L
2089|Lingran|L
2654|LingshanIs|L
5042|LingwuLuqi|L
4021|Lingxiwhow|L
3882|LingyueRed|L
4189|LinQinghua|L
5460|LinSake|L
3900|LinSanjiu|L
6103|LinShendu|L
2668|LinXiufigh|L
5970|LinYiliu|L
5757|LinYouyu|L
2572|LinZhengyi|L
5968|lionazaaza|L
4309|LiShaoming|L
6771|LiShimin|L
3842|ListAdvent|L
1335|ListCreati|L
5956|Listentoth|L
5836|listentoth|L
4141|listentoth|L
4032|Listentoth|L
3524|listentoth|L
2717|listentoth|L
5692|Literaryes|L
6590|literature|L
1416|literature|L
3695|Literature|L
983|LitRPG|L
2197|littleahxi|L
5746|littleassa|L
5390|Littleblue|L
4542|littlebow|L
2291|littlebrot|L
4474|littleches|L
3920|littleclou|L
2823|littlecray|L
4797|Littledemo|L
2130|littledemo|L
2803|littledete|L
2357|littledevi|L
3984|littledoct|L
5644|LittleDoud|L
5237|LittleFeng|L
2388|littlefing|L
5461|littleflow|L
2152|littlefox|L
4645|littlefoxi|L
5670|Littlefurb|L
6778|littlegirl|L
2002|littlehson|L
4083|LittleJack|L
6080|littlelitt|L
4588|littlemiss|L
5109|LittleMo|L
2041|littlemoon|L
4044|Littlepros|L
5024|LittleRedR|L
990|LittleRoma|L
3263|Littlesold|L
4175|LittleSpri|L
2320|littlesuns|L
5242|LittleTeem|L
4239|LittleThro|L
2848|littlewate|L
4638|littlewhit|L
4531|littlewhit|L
3596|LittleWhit|L
2558|littlewind|L
6096|Littlewood|L
4069|littleworl|L
3939|LittleZhug|L
2031|littlezlov|L
5496|Liuhuaacri|L
5613|LiuXiaozu|L
2418|LiuYujun|L
5749|LiuYuxuemo|L
3936|LiuZiqing|L
1604|Live Streaming|L
883|Live Streaming|L
919|Livebroadc|L
941|LiveBroadc|L
4191|LiveGemini|L
2033|LiverPigeo|L
3136|Livetext|L
474|Living Alone|L
1877|LiWudi|L
5431|LiXiaojian|L
5100|LiYouqiong|L
4998|LiyuePlann|L
5786|LiYuer|L
4111|LiZhitaoJu|L
6714|LiZicheng|L
4056|LoadingApp|L
3139|Loli|L
576|Loli|L
425|Lolicon|L
1518|LoliProtag|L
2242|LoneCloudP|L
6211|Loneliness|L
5856|Lonely|L
2855|lonelyboy|L
3532|LonelyChen|L
2007|LonelyCity|L
1990|Lonelynota|L
4505|lonelyreco|L
5849|lonelyseas|L
4798|lonelyshoo|L
585|Loner Protagonist|L
5471|lonewolfl|L
3632|Long|L
412|Long Separations|L
273|Long-distance Relationship|L
4708|Longanloli|L
6253|LongAotian|L
4475|Longcenter|L
3299|Longevity|L
2877|longlivedm|L
2456|longlivemy|L
2556|Longlivesa|L
5733|longliveth|L
2655|Longliveth|L
2439|Longliveth|L
2287|LongMengme|L
4423|Longmensin|L
4380|longnightl|L
4688|Longpigeon|L
2390|Longpigeon|L
3863|LongquanNo|L
5655|LongShao12|L
4275|longsongan|L
3843|LongStrip|L
5399|Longtimeco|L
5000|LongYu|L
4464|Lookatthep|L
6020|Lookingbac|L
4615|lookingout|L
4649|Lookthroug|L
3333|lootflow|L
895|Lord of the Mysteries|L
1724|LordAbilit|L
5641|LordCrimso|L
3819|Lorddevelo|L
3410|Lordfarmin|L
3705|LordGod|L
1588|LordGodSpa|L
3722|LordGrim|L
3868|LordofDark|L
6336|LordofMyst|L
4618|LordoftheS|L
1976|LordoftheS|L
4207|LordofWar1|L
2614|LordTiansh|L
2332|LordZhangj|L
4576|LosAngeles|L
1925|Loseafewpo|L
5166|losemoney|L
5691|loser|L
330|Lost Civilizations|L
4858|Lostbeliev|L
5260|lostblack|L
5208|Lostfarewe|L
573|Lottery|L
817|LotterySys|L
1498|Love|L
168|Love at First Sight|L
3087|Love at First Sight|L
1660|Love Interest Falls in Love First|L
1624|Love Interest Falls in Love First|L
19|Love Interest Falls in Love First|L
610|Love Rivals|L
485|Love Triangles|L
1385|LoveandMar|L
4665|loveapplep|L
3217|lovebefore|L
5332|lovebefore|L
3024|lovebefore|L
4510|Lovecomedy|L
1576|LoveContra|L
3127|Loveeachot|L
6140|LoveintheR|L
4462|loveletter|L
6345|lovely|L
4413|lovemints|L
502|Lovers Reunited|L
2183|Lovesnacks|L
4643|lovespicyf|L
2785|lovetease|L
4870|lovetoeatr|L
5991|Lovetosuck|L
6492|LoveTribul|L
5600|LoveVegeta|L
1397|lovingfami|L
328|Low-key Protagonist|L
2818|Low-keylux|L
1649|LowFantasy|L
3703|lowintelli|L
1090|LowKeyMc|L
1182|LowkeyProt|L
507|Loyal Subordinates|L
3305|loyaldog|L
1289|LoyalProta|L
1599|LoyalSurbo|L
6685|loyalty|L
5180|lspstoryte|L
5285|lsuyangl|L
2734|lu11034363|L
1720|LuckPlunde|L
368|Lucky Protagonist|L
1579|Lucky Protagonist|L
3240|luckybag|L
4071|LuckyE&|L
6291|LuckyPack|L
3650|Luckytolau|L
2125|LuDehua|L
4209|LujingVill|L
3468|lumpofjade|L
4713|Lungdefici|L
4633|LuoAichen|L
5473|LuoFeige|L
4791|LuoJiangsh|L
6052|LuoLiisnot|L
4302|LuoMuziyi|L
5990|Luoran123|L
5493|LuoShichao|L
3887|LuoShu|L
1865|LuoTianyi|L
3788|LuoTianyic|L
1994|LuoWei|L
5232|LuoXiaoqia|L
2530|LuoXIV|L
2752|LuoYuqianq|L
4322|LutherHark|L
909|Luxury|L
4378|luxurypenm|L
2474|LY|L
4351|machine|M
6088|MadBoyTang|M
4390|madman|M
4114|madmanandf|M
5084|Mag|M
1013|Mage|M
4955|Maggie|M
182|Magic|M
314|Magic Beasts|M
72|Magic Formations|M
988|MagicAcade|M
1744|Magical Girls|M
73|Magical Space|M
608|Magical Technology|M
1453|MagicalAbi|M
1587|MagicalBat|M
3444|magicalcre|M
6610|MagicalWor|M
6739|Magicdomai|M
5817|MagicDrago|M
3700|magician|M
2595|MagicOne|M
5626|magicpet|M
2393|MagicTides|M
4930|magicwhip|M
1114|MagicWorld|M
1560|Maids|M
649|Maids|M
5962|MaifengXia|M
2638|Makeafortu|M
2248|makeamirac|M
3242|Makecompla|M
3179|makefine|M
4431|makemehapp|M
3099|Makemoney|M
2945|MakemoneyC|M
3082|MakemoneyI|M
2998|MakemoneyM|M
2937|MakemoneyM|M
3053|MakemoneyR|M
2977|MakemoneyR|M
2950|MakemoneyR|M
3018|Makemoneys|M
4612|makepigeon|M
4812|Makeupforf|M
1685|Malaysian|M
1684|MalaysianN|M
12|Male Protagonist|M
2900|Male Protagonist|M
965|Male Protagonist|M
1287|Male Protagonist|M
1261|Male Protagonist|M
1079|Male Protagonist|M
480|Male to Female|M
28|Male Yandere|M
1350|Male-Lead|M
1378|Male-Prota|M
3118|Malegod|M
716|MaleLead|M
1208|MaleMain-l|M
2878|Malemainch|M
3628|malematch|M
1091|MaleMc|M
5915|maliciousw|M
2718|mambafight|M
2194|man|M
4442|man-eating|M
3091|Management|M
642|Management|M
4620|Manchengma|M
1434|mandaloria|M
809|Mangaka|M
2435|MangoKK|M
5759|manhasbeco|M
3844|Manhua|M
4954|maninknigh|M
2486|maninnarut|M
5410|maninorang|M
1480|Manipulative Characters|M
597|Manipulative Characters|M
96|Manly Gay Couple|M
3194|Manvs.Wild|M
4947|manwithkid|M
2957|manyfemale|M
5542|MaodongChe|M
5194|MaoLinwhol|M
5233|Maonanbei!|M
5818|maple|M
4315|maplebirch|M
3799|maplefores|M
2854|mapleleafb|M
5227|marchisado|M
3478|Marioeatsc|M
4731|Marlene&am|M
1953|MarquisofB|M
85|Marriage|M
489|Marriage of Convenience|M
1543|MarriageCo|M
1235|Married|M
1751|MarriedCou|M
3386|marry|M
3218|marrybycha|M
6756|Marryingin|M
6522|marshal|M
394|Martial Spirits|M
1364|Martial Spirits|M
130|Martialart|M
6287|Martialart|M
1471|MartialArt|M
6181|Martialart|M
5710|Martialart|M
3055|martialart|M
6606|MartialSou|M
537|Marvel|M
2135|MarvelKing|M
2540|MarvelPudd|M
553|MarvelUniv|M
5875|MarvelWang|M
1779|marvelworl|M
5077|Marysue|M
3627|Masashi|M
1864|MaskedAce|M
2860|MaskedArmo|M
4538|MaskedPich|M
45|Masochistic Characters|M
2253|Masquerade|M
3516|Mass-produ|M
1634|Massacre|M
1073|Massive|M
891|MassiveHar|M
6466|Master|M
1228|Master-App|M
304|Master-Disciple Relationship|M
361|Master-Servant Relationship|M
2277|Masterball|M
3307|Masterflow|M
5213|MasterGree|M
3512|Masterishe|M
4103|Masterofea|M
5261|MasterofSa|M
2806|MasterofSi|M
4835|MasterPeng|M
6124|MasterTian|M
6018|MasterZhiq|M
733|Masturbation|M
1736|Matchmadei|M
1781|math|M
686|Matriarchy|M
5188|MatthewisG|M
977|Mature Protagonist|M
97|Mature Protagonist|M
1509|MCStrongFr|M
6015|meatsauce|M
3289|Mech|M
804|Mecha|M
4214|Mechanical|M
3738|MechGod|M
299|Medical Knowledge|M
4013|Medical Knowledge|M
1110|Medical Knowledge|M
5050|medicalfem|M
6577|Medicalpra|M
6524|medicalski|M
795|Medicine|M
2688|medicineme|M
5484|medicinest|M
429|Medieval|M
4060|meetingdee|M
2151|meetthebea|M
5620|Melancholy|M
1519|MemoryLoss|M
1740|MemoryReve|M
3176|MengBao|M
2999|MengBaowea|M
3917|MengLiangq|M
4463|MengmeiBin|M
6276|Mengwa|M
4010|MengXiaohu|M
5248|Mengxinsma|M
5506|MengYuxin|M
3322|Mensao|M
1815|MentalIlln|M
3191|Mentor|M
4259|Meowalook|M
6097|meowhokage|M
4670|meowhum|M
2087|Meowingbig|M
2080|meowmeow|M
4647|meowmeowsl|M
167|Mercenaries|M
797|Mercenary|M
527|Merchants|M
2886|Merchants|M
2876|mermaid|M
3234|metaphysic|M
3065|metaphysic|M
3639|Metauniver|M
6687|Meteorite|M
4009|Meteorstre|M
5121|metropolis|M
1447|Middleage|M
5128|middleaged|M
5098|MiddleAges|M
4377|midnight|M
5030|midnightbl|M
4740|midnightli|M
4280|midnightma|M
4848|midnightsu|M
5254|MidoriSaku|M
6114|Miha|M
6098|MikaMio|M
5089|Milf|M
86|Military|M
6554|MilitaryCo|M
6760|militarydo|M
3402|militaryfa|M
3401|Militaryin|M
6621|Militaryma|M
2831|Milkgather|M
2278|milkgrandm|M
5932|Milkteapot|M
5667|Millennium|M
3581|Millennium|M
1459|Millionair|M
5228|milliondig|M
2370|millionord|M
2267|Miluo|M
1711|Mimicry|M
621|Mind Break|M
389|Mind Control|M
1484|MindReader|M
2873|mindreadin|M
6246|Minecraft|M
3089|MingDynast|M
3076|MingDynast|M
2962|MingDynast|M
2934|MingDynast|M
1945|Mingjiao|M
2026|MingjiaoTi|M
4822|MingXi|M
1609|Ministryof|M
6546|miracle|M
6195|Miracledoc|M
4865|Misaki|M
6683|mischief|M
3140|miser|M
4694|Miska10010|M
1343|Mismatched Couple|M
6603|Miss|M
6656|mission|M
5025|Mista|M
2157|Mistresspl|M
2189|MistyFlyin|M
1445|Misunderstandings|M
113|Misunderstandings|M
1565|Misunderstandings|M
1072|Misunderstandings|M
2601|mixedintwo|M
4823|MizukiSpir|M
202|MMORPG|M
443|Mob Protagonist|M
1584|Mob Protagonist|M
3717|MobileGame|M
657|Models|M
1370|ModerDays|M
601|Modern|M
3|Modern Day|M
307|Modern Knowledge|M
825|Modern Knowledge|M
6229|ModernCity|M
3319|moderncomp|M
6290|ModernCult|M
754|ModernDays|M
1027|ModernFant|M
2908|ModernLife|M
1780|modernlove|M
5118|modernmagi|M
3413|modernmyst|M
6753|ModernMyst|M
6255|Modernover|M
959|ModernRoma|M
386|ModernWorl|M
2790|Moedye|M
5597|MoeHan|M
2930|MoeShinkaw|M
2625|Mofamily|M
6014|MoFenghou|M
5176|Moisturizi|M
2396|MojiaAeros|M
2355|MojiaHills|M
4736|moltingsna|M
3849|Momiji|M
6679|monarch|M
82|Money Grubber|M
6647|Money Grubber|M
1199|MoneyGrumb|M
3633|Monk|M
3759|MonkeyKing|M
1197|Monogamy|M
1136|Monster|M
569|Monster Girls|M
1151|Monster Society|M
74|Monster Tamer|M
5727|monsteridl|M
230|Monsters|M
1689|MonsterTar|M
5240|monthand|M
6575|mood|M
4581|moonandsta|M
1931|moonbug|M
4763|mooncrow|M
2661|MoonlightS|M
5598|moonlightw|M
2467|Moonlikeah|M
5508|moonnight|M
1923|Moonsea|M
4321|moonsetsea|M
4980|moonshadow|M
4619|moonshadow|M
5408|moonshower|M
6030|Moonstay|M
3793|moontea|M
1789|Moonwing|M
4449|MoQingyi|M
6220|Morality|M
1738|Morallessp|M
1494|MorallyAmb|M
2226|moreandmor|M
3804|moreastron|M
6001|Morningclo|M
5135|morninglig|M
4946|morningred|M
3150|Mortal Flow|M
4655|MoshangHua|M
3169|Mother-in-|M
2990|Mother-in-|M
3010|Motherland|M
4780|Mountainan|M
5136|mountainsa|M
2154|Mountainsa|M
1857|Mountainsa|M
4077|MountainSe|M
3167|mouthgun|M
292|Movies|M
6677|Moving|M
2127|movingbean|M
3660|MoXianyu|M
2030|MoXueqing|M
2570|Moyangison|M
3351|Mozun|M
257|Mpreg|M
6112|Mr.Despair|M
1987|Mr.EasyPro|M
5171|Mr.flag|M
2542|Mr.Huo|M
3800|Mr.Quin|M
5844|Mr.ShuiYun|M
4240|Mr.Xiaisfr|M
5921|Mr.Zhaowho|M
5391|MrBearBear|M
4260|mrcoud|M
4671|MrEarl|M
1800|MrMo|M
1610|MrSly|M
4838|MrStardust|M
1611|MsPerfect|M
1022|Msturbatio|M
4369|MuChenchen|M
2215|mudbodhisa|M
4528|MUGEN|M
1633|Mukbang|M
6772|mulatto|M
6205|Multi-Wife|M
387|Multiple Identities|M
1729|Multiple Identities|M
1295|Multiple Identities|M
20|Multiple Personalities|M
279|Multiple POV|M
1277|Multiple POV|M
501|Multiple Protagonists|M
615|Multiple Timelines|M
1152|Multiple Transported Individuals|M
293|Multiple Transported Individuals|M
1393|MultipleBo|M
756|MultipleCP|M
6375|Multiplefe|M
6294|Multiplefe|M
1188|MultipleHi|M
1650|MultipleLe|M
1167|MultipleMo|M
29|MultipleRe|M
1657|multiplere|M
435|MultipleRe|M
1470|MultipleVe|M
1092|MultipleWo|M
1617|MultipleWo|M
1026|Multiverse|M
5182|MuMushuhua|M
5842|MuNanzhi|M
5446|Munchkin|M
4159|mungbeanga|M
366|Murders|M
345|Murders|M
6091|Mushroomma|M
186|Music|M
1915|musicwilll|M
2199|mustdo|M
3889|mustfire|M
1574|Mutan|M
1345|MutantPowe|M
320|Mutated Creatures|M
418|Mutations|M
844|Mutations|M
736|Mute Character|M
1161|Mutualcrus|M
4078|MuxiMuxi|M
4924|MuZixi|M
5512|mygrandma|M
3487|MyGreatQin|M
1340|MyHeroAcad|M
2225|mylittlesi|M
2630|MyLubanThi|M
3782|mymeatisde|M
2079|MynameisDa|M
2270|mynameista|M
3511|MynameisZh|M
6393|MyriadReal|M
3732|mysteries|M
388|Mysterious|M
3634|Mysterious|M
656|Mysterious|M
363|Mysterious|M
5127|mysterious|M
4890|Mysterious|M
4769|Mysterious|M
1096|Mysterious|M
936|Mystery Solving|M
185|Mystery Solving|M
764|Mystical|M
4929|MysticBlue|M
4393|Myswordisc|M
5079|Myth|M
427|Mythical Beasts|M
666|Mythical Beasts|M
2575|mythicalfi|M
2440|mythicalma|M
484|Mythology|M
1651|Mythos|M
6707|Mythsandle|M
2408|mythunpara|M
2448|mywife|M
3784|mywifeisab|M
2754|mywifeisya|M
791|NA|N
6099|Nagasakiha|N
4963|NagatoYuki|N
4559|NagiNagibe|N
5500|NaiNaiHeTi|N
5351|NaiTsujiCi|N
75|Naive Protagonist|N
3614|Nakaji|N
5971|namelessna|N
4805|NamoAmitab|N
5621|NanaSauceL|N
2307|Nanshen|N
1497|Napoleon|N
469|Narcissistic Protagonist|N
4481|Nari|N
335|Naruto|N
2484|narutoceda|N
2479|NarutoClou|N
3617|narutodrag|N
5640|NarutoNovi|N
2485|NarutoQuiz|N
5984|Narutosix|N
4306|narutovill|N
2588|NarutoxRea|N
4907|Nasida|N
3590|NationalDi|N
305|Nationalism|N
3641|nationalmy|N
1115|NationBuil|N
3727|Nativebamb|N
6452|NATURE|N
3649|natureover|N
1097|Navy|N
4129|nb9527|N
617|NBA|N
76|Near-Death Experience|N
422|Necromancer|N
4444|Necromancy|N
3751|Need|N
4376|Needsquirr|N
4942|Neepeatsme|N
645|Neet|N
5502|NegaNebulu|N
3940|neromywife|N
4127|NetherNine|N
77|Netorare|N
78|Netori|N
3712|Netred|N
4644|networkdis|N
4539|neverdream|N
2567|neverfail|N
4415|nevertooba|N
5964|Neveruseso|N
6071|newbie|N
5462|newnine|N
4471|newspapera|N
6141|nextyear|N
2337|NiangkouSa|N
5125|nicheoccup|N
4934|Nidoriya|N
2587|Nidouzi|N
6000|NightAllur|N
5998|NightDance|N
2725|nightdance|N
1863|nightfire|N
5571|nightlangu|N
461|Nightmares|N
346|Nightmares|N
4651|nightrain|N
5999|NightSheng|N
1891|nightsilen|N
4237|nightsleep|N
4758|nightwhite|N
1437|nihilism|N
6013|NikaBaka|N
3579|Nim|N
4298|Nine|N
2436|Nine-color|N
2178|Nine-Taile|N
3931|Ninedays|N
1959|NinefoldSe|N
6407|NineHeaven|N
5253|NineHeaven|N
4038|nineonemor|N
3618|ninepositi|N
5821|NineShaoSh|N
4051|nineshipju|N
4523|NineStarMa|N
2082|NineWarsof|N
3956|NingYi|N
1868|Ninjapirat|N
460|Ninjas|N
1756|Ninjas|N
3977|ninthinthe|N
6066|ninthsweet|N
5043|NiShiliu|N
2085|NiuBao|N
3808|no|N
5082|No-Harem|N
3622|No.XNUMXon|N
5762|No.XNUMXXi|N
6190|nobledaugh|N
4832|Noblenessi|N
280|Nobles|N
1600|Nobles|N
4357|NoblesPoli|N
5742|Nocar|N
5961|nocarton|N
6540|Nocheatcod|N
4354|NoCheats|N
1605|NoCp|N
5317|NoCPRelaxe|N
5316|NoCPreveng|N
3249|Nodiscipli|N
3906|nodream|N
6318|Nofemalele|N
3145|Nogoldenfi|N
1290|NoHarem|N
3262|noheroine|N
5743|nohouse|N
5495|noisyfish|N
1017|nokillingm|N
2696|Noless|N
4768|nolove|N
4733|nomooninma|N
1667|Non-Humanl|N
4359|Non-HumanM|N
143|Non-humanoid Protagonist|N
851|Non-humanP|N
5448|Non-legacy|N
6212|Non-linear Storytelling|N
1311|Non-System|N
2578|noncat|N
1111|NonHuman|N
1078|NonHumanPr|N
5799|nonpondfis|N
6422|noob|N
5374|noon|N
1278|NoPairing|N
4855|noregrets|N
4079|normalluck|N
1015|NoRomance|N
5426|NorthDepar|N
5592|Northeastb|N
3659|Northeastb|N
3768|NorthMu|N
5487|NorthSeaMo|N
4719|Northstar|N
4408|noshadow|N
2081|Nosnacks|N
4825|nostring|N
1537|NoSystem|N
4526|notbad|N
4986|notcold|N
6495|notes|N
4029|notfalling|N
4224|notgreedy|N
3725|notguilty|N
996|NotHarem|N
4524|NotIke|N
2564|notlevelth|N
5468|notnew|N
3762|Notraceofm|N
2488|notscary|N
4478|nottowersa|N
3466|notwo|N
1032|NotYaoi|N
6184|Novel|N
6209|novelsknig|N
2604|Nowadays|N
5744|nowife|N
3141|NPC|N
5087|NSFW|N
4358|NTL|N
3830|NuclearBea|N
972|Nudity|N
6541|number|N
5133|Numberofwo|N
3908|Nunknightw|N
637|Nurses|N
3510|NuShengsoo|N
2158|Obanbrothe|O
5960|Observer23|O
4735|observerwx|O
3831|Obsession|O
205|Obsessive Love|O
2898|offical|O
3606|Office Romance|O
517|Office Romance|O
6696|officialdo|O
4842|OhLL|O
2446|ohmygod|O
1910|oldage|O
5099|OldAlfred|O
3997|oldchicken|O
5016|oldclawmac|O
2129|olddemon|O
364|Older Love Interests|O
4324|Older Love Interests|O
5379|oldfacesli|O
2698|oldfaceunc|O
5288|oldfashion|O
2044|oldfisheat|O
2469|Oldghostsm|O
4606|Oldies|O
4553|oldlady|O
3770|oldmaneati|O
4480|oldmonth|O
1999|OldQinpeop|O
4997|OldTeaTree|O
2487|oldtombrob|O
5297|oldwalnut|O
6295|Oldwhitepo|O
5650|OldWuupsta|O
5434|OldYdoesno|O
301|Omegaverse|O
4341|Omegaverse|O
1615|On-HookSys|O
3677|One|O
336|One Piece|O
1328|One Punch Man|O
1063|One Punch Man|O
2874|One-Piece|O
5661|Onebyone|O
2722|Oneflower|O
2499|OneLeafRed|O
4739|OneLeafSea|O
2724|onemelonri|O
2794|onemeterst|O
5898|oneminustw|O
4047|onemouthfu|O
5880|OnenightHo|O
5014|Oneofthebe|O
2495|Onepunchmo|O
2709|Onepunchto|O
4409|OneSwordEm|O
2039|OneSwordFl|O
5560|OneSwordLi|O
2083|Onethousan|O
2723|onetree|O
2715|Oneyearold|O
638|Online Romance|O
1117|Online Romance|O
3168|Onlinegame|O
3394|onlinegame|O
762|OnlineGame|O
6193|Onlinegame|O
1952|onlyloveyo|O
2736|onlyyouth|O
3406|Onocat|O
2283|onparadise|O
2392|oooobe|O
3259|Open|O
1806|openasmall|O
3361|openflow|O
3149|openingflo|O
3020|openingflo|O
6623|OpeningStr|O
6305|OpentheVen|O
3264|Openupwast|O
2327|Openyourey|O
2896|Operation|O
3925|Operationr|O
1189|OpFemalePr|O
1469|OPheroine|O
892|OPMC|O
6725|opportunit|O
1183|OPProtagon|O
2239|orangeappl|O
3765|orangeglor|O
5510|OrangeOche|O
3490|Orangespar|O
720|Orcs|O
1298|Orcs|O
966|Orcsworld|O
5887|Ordinary|O
6406|Ordinarype|O
1056|Organizati|O
174|Organized Crime|O
5705|Orientalde|O
694|Orientalfa|O
4273|orientalfa|O
6035|Orientalle|O
4927|Orientalre|O
3747|orientalsa|O
5863|origamista|O
3238|originalco|O
3046|originalco|O
3702|Originalfi|O
6280|Originalgo|O
1647|OriginalON|O
6289|OriginalSt|O
2325|OriginalUn|O
2705|OriginalYe|O
2742|Origuchi|O
933|OrphanMC|O
428|Orphans|O
1247|Orphans|O
472|Otaku|O
4585|Otakuisnot|O
2117|Otezetta|O
5685|otherworld|O
6735|Otherworld|O
3929|Otoichi|O
1580|Otome Game|O
6279|Otome Game|O
2472|OTTGroupCh|O
5802|Ottointhek|O
4561|ourraccoon|O
991|Outcasts|O
5092|Outdoors|O
409|Outer Space|O
4429|outingbook|O
3684|Outlawluna|O
5179|Outstandin|O
5458|OuyangRuox|O
4325|Over-Power|O
3443|overbearin|O
3225|Overhead|O
2905|OverheadHi|O
5321|OverheadSu|O
1184|Overlord|O
821|Overpowerd|O
876|Overpowered Protagonist|O
6156|Overpowered Protagonist|O
864|Overpowered Protagonist|O
1394|Overpowered Protagonist|O
1214|Overpowered Protagonist|O
41|Overpowered Protagonist|O
717|Overprotective Siblings|O
3778|Overseasca|O
5252|owe|O
3636|Owner|O
4025|ownerofwhi|O
1186|Pacifist Protagonist|P
1262|Painter|P
1229|Painting|P
752|Paizuri|P
5048|palace|P
6174|Palacefigh|P
3452|palacemaid|P
2264|paleandwhi|P
3817|palebluefl|P
6519|Pamperedno|P
591|PamperingR|P
3865|Panda&0|P
6105|pangolin|P
6625|PanguCreat|P
2166|panic|P
2647|Papaisvery|P
5164|papergrayo|P
823|ParalelWor|P
458|Parallel Worlds|P
819|Parallel Worlds|P
6642|parallelun|P
1168|Paranoid|P
331|Parasites|P
1554|Parasites|P
650|Parent Complex|P
5454|Parenting|P
620|Parody|P
268|Part-Time Job|P
2025|part-timeo|P
1366|Partnerofa|P
4940|Passer-by|P
5557|passerbylo|P
5527|passingmap|P
98|Past Plays a Big Role|P
497|Past Plays a Big Role|P
114|Past Trauma|P
3171|PastandPre|P
2994|PastandPre|P
3812|patientswi|P
855|Patriarch|P
6693|patriotic|P
6558|Patronsain|P
5269|Peacefulan|P
3671|Peachgift|P
6069|peachmelon|P
3303|Peasant|P
4544|PeasPigeon|P
6435|Peerless|P
6763|Peerlessma|P
1795|Peerlessso|P
1791|PeerlessSw|P
3675|penandinkw|P
5474|pencildraw|P
2827|pendragon|P
2096|pendreamst|P
5231|penhero|P
4626|Pennamenot|P
4905|pentaclekn|P
6669|People|P
5144|Peoplearef|P
3522|peopleflyi|P
2632|Peoplenear|P
5824|Peoplepass|P
5723|peoplewhoe|P
4960|Pepsi|P
1803|perfectmag|P
5581|perfecttom|P
1332|PerfectWor|P
6747|perseveran|P
3872|Persistenc|P
274|Persistent Love Interests|P
6379|Personality Changes|P
137|Personality Changes|P
5772|personusin|P
6738|perspectiv|P
281|Perverted Protagonist|P
4786|pervertedi|P
107|Pets|P
1206|Pets|P
2511|petsurviva|P
3370|PhantomThi|P
689|Pharmacist|P
774|Philosophical|P
236|Phoenixes|P
4264|Phosphorus|P
3556|Photography|P
705|Photography|P
6484|physicaled|P
3710|Physician|P
4436|Pickingupp|P
5526|PickingupY|P
6365|Pickupleak|P
4262|pigc|P
5896|pigeonbeek|P
2599|pigeonnext|P
4673|Pigeonsare|P
4113|pigeonsnev|P
399|Pill Based Cultivation|P
400|Pill Concocting|P
674|PillConcot|P
1592|Pilots|P
6266|Pingbuqing|P
2234|Pipifish|P
4272|PipiGray|P
6079|Pipisanqin|P
1166|Pirate|P
2489|Pirateacto|P
2497|PirateCour|P
1844|PirateDaQi|P
2147|PirateGrea|P
1914|Piratehaha|P
546|Pirates|P
2748|PiratesofH|P
4418|PirateSumm|P
2491|PirateWars|P
2559|PiratexFai|P
2681|Piscesinth|P
4695|Piscesscum|P
3728|pittree|P
3772|pity|P
3120|Plane|P
6024|planeapple|P
1004|Planets|P
3972|PlaneWars|P
1137|Plants|P
5973|Playaswate|P
2069|PlayBlueMo|P
1275|Playboymal|P
653|Playboys|P
1562|Player|P
1690|PlayerKill|P
1245|Players|P
714|Playful Protagonist|P
6421|Playful Protagonist|P
4922|Playingcat|P
1482|PlayingGho|P
6224|PlayingStr|P
5358|playYaoer|P
2054|pleasantin|P
5018|pleasecall|P
2933|Pleaseforg|P
6084|pleasehave|P
4097|pleasehitm|P
4396|Pleasesixt|P
2156|plumthirte|P
5428|Pochita|P
1438|poems|P
731|Poetry|P
4686|Poison1|P
3892|PoisonConc|P
3409|poisondoct|P
1070|PoisonMout|P
3426|Poisonoust|P
370|Poisons|P
587|Pokemon|P
5957|pokemonelf|P
2761|PokémonGo|P
2492|PokémonTi|P
4221|PokémonUn|P
2155|PokémonVo|P
3407|polarflow|P
4983|PoleStarWh|P
419|Police|P
3587|Policemen|P
3198|policyflow|P
684|Polite Protagonist|P
949|PoliticalI|P
1279|PoliticalS|P
43|Politics|P
669|Polyandry|P
282|Polygamy|P
4987|pomeloslee|P
3603|Pony|P
4355|Poor|P
522|Poor Protagonist|P
132|Poor to Rich|P
1787|Poorcrazy|P
1535|PoorRoRich|P
2494|PopeBibiDo|P
4244|Popi|P
592|Popular Love Interests|P
5072|Popular Love Interests|P
3335|Popularsci|P
4712|Poriacocos|P
5204|porkbuns|P
4008|porridge|P
951|PortableSp|P
3421|PortalFant|P
5888|Positive|P
2098|Positiveel|P
3202|positiveen|P
1455|PositiveLe|P
6556|Positiveva|P
605|Possession|P
4|Possessive Characters|P
1211|Possessive Characters|P
5886|Possessive Characters|P
401|Post-apocalyptic|P
3993|Potatoesar|P
2729|potatogirl|P
5796|PotatoRawS|P
4365|poundedric|P
5218|pouringice|P
1280|PovertyAll|P
47|Power Couple|P
690|Power Struggle|P
6727|Powerfulco|P
1355|Powerfulco|P
3104|Powerfulmi|P
4375|PowerGener|P
3270|Powerhouse|P
1066|PowersTran|P
3760|pps|P
3346|practice|P
3611|practicefl|P
593|Pragmatic Protagonist|P
4806|PraiseforD|P
724|Precognition|P
6401|predecesso|P
4869|Preferthew|P
83|Pregnancy|P
4482|prehistori|P
1362|Prehistori|P
1352|Prehistori|P
1732|PresentDay|P
6445|Presidedov|P
1715|President|P
250|Pretend Lovers|P
2976|Pretendtob|P
5073|PrettyGirl|P
138|Previous Life Talent|P
685|Previous Life Talent|P
3708|Priest|P
1059|Priestesses|P
707|Priests|P
3775|PrimeMinis|P
1138|Primitives|P
4336|PrimitiveT|P
967|Primitivew|P
3163|prince|P
2847|PrinceofHe|P
1306|PrinceofTe|P
2631|PrinceQing|P
1527|Princess|P
560|Prison|P
423|Proactive Protagonist|P
4844|probabilit|P
5714|prodigal|P
5857|Prodigalso|P
6153|Profession|P
3201|Profession|P
6242|Profession|P
6789|Profession|P
6315|Profession|P
4202|Profession|P
928|Professor|P
704|Programmer|P
5416|Programmer|P
3848|Programmin|P
1652|Progressio|P
3569|propertyst|P
718|Prophecies|P
6694|prophecy|P
6560|prophet|P
4131|Prosperity|P
4784|Prosperous|P
3300|Prostitutes|P
447|Prostitutes|P
1640|Protagonis|P
1037|Protagonis|P
2881|Protagonis|P
1525|Protagonis|P
1341|Protagonis|P
1305|Protagonis|P
1129|Protagonis|P
462|Protagonis|P
283|Protagonis|P
49|Protagonis|P
6332|Protecting|P
3227|protectsho|P
6780|Protectthe|P
4512|Protectthe|P
3316|Proud|P
1281|PseudoHolo|P
1282|PseudoReli|P
2910|psionic|P
715|Psychic Powers|P
1067|Psychic Powers|P
5979|Psychokill|P
1045|Psychologi|P
1544|Psychology|P
498|Psychopaths|P
1960|Punch|P
4301|Puppeteers|P
6218|Puppeteers|P
3599|puppy|P
5657|PurebloodS|P
2538|pureimpuls|P
2465|purekitten|P
3838|PureLove|P
5719|purelovefa|P
4015|purepigeon|P
5524|puresenior|P
4213|purewhiteo|P
4493|Purple|P
5853|Purple-hai|P
5168|purplebrok|P
5789|PurpleDuri|P
4155|PurpleEmpe|P
4808|PurpleNaya|P
3540|purpleslim|P
5924|Putdownthe|P
6300|Putpentopa|P
6613|putup|P
1529|Puzzles|P
5981|qhfishinga|Q
5868|QianandQia|Q
5721|Qiandengwi|Q
6517|Qianjin|Q
6583|Qiankun|Q
3645|Qianlong|Q
4582|Qianqianra|Q
2735|QianshanTw|Q
3718|QianXixi|Q
3683|QianXunxia|Q
5044|qidian|Q
4045|Qilixiang|Q
1641|QiLuck|Q
5120|qimao|Q
1859|QinBichu|Q
4289|QinBuxiang|Q
3174|QingDynast|Q
2993|QingDynast|Q
1853|Qingfeng1D|Q
4864|QingfengYu|Q
2032|QingheTaoi|Q
5303|QinghuiYen|Q
1970|Qingliansw|Q
3693|Qingluan|Q
5820|Qingsanren|Q
5368|QingWeixin|Q
4852|Qingxinyuu|Q
2360|qingyu|Q
3230|QinHan|Q
3039|QinHanCros|Q
4447|QinHanTang|Q
5569|QinShiSwor|Q
5610|QinTangFei|Q
3995|QiuZiXiaXu|Q
2111|QiXuan|Q
5603|Qiyao&0|Q
5730|QiyueLiuhu|Q
4752|QiyueShiqi|Q
6221|QiyunFlow|Q
4817|QiYuwholov|Q
1758|QT|Q
5601|Quackhamst|Q
5396|quantumgoo|Q
5486|QuartetSev|Q
5568|Quasar|Q
1919|Quasi-GodS|Q
3574|Queen|Q
2445|QueenofBla|Q
1728|Question&a|Q
1621|QuickPass|Q
599|QuickTrans|Q
944|QuickTrans|Q
1659|QuickTrans|Q
1547|Quickwear|Q
719|Quiet Characters|Q
1847|quietflowe|Q
198|Quirky Characters|Q
2613|Quququ|Q
727|R-13|R
646|R-15|R
5455|R-18|R
5058|R18|R
2539|RabbitToot|R
5028|raccoonrac|R
3797|raccoonsho|R
604|Race Change|R
13|Racism|R
3250|Raiders|R
971|Raids|R
4490|Railgun|R
2254|rainandsno|R
4537|Rainandsun|R
3769|rainbeans|R
2682|rainboweig|R
5634|rainclearn|R
4104|Rainfallsf|R
4164|Rainhitsba|R
5154|Rainink|R
4368|rainiscomi|R
5480|rainyday|R
2788|rainydaywi|R
4892|rainystars|R
2611|Raiseaghos|R
2600|raisedache|R
5398|rakepig|R
6182|RanchFarmi|R
5631|randomstre|R
5373|randomwhy|R
1743|RankingLis|R
997|RankSystem|R
3969|Ranwho|R
402|Rape|R
827|Rape Victim Becomes Lover|R
6|Rape Victim Becomes Lover|R
2159|Rapeseedra|R
5060|Rarebloodl|R
4362|Rarely|R
1688|Ras|R
4468|Raven|R
3959|RavenCrow|R
3449|rawstream|R
4157|Raynes|R
6491|read|R
3205|readstream|R
5122|Realestate|R
6417|Reality-Game Fusion|R
2284|reallyking|R
5624|reallynotg|R
2810|Realmmonst|R
5433|realnamest|R
5552|realoldgen|R
5891|reasoning|R
757|Rebellion|R
6782|Rebellious|R
5906|Rebellious|R
139|Rebirth|R
2984|RebirthChr|R
2987|Rebirthdoc|R
1241|RebirthedP|R
3014|Rebirtheve|R
3017|Rebirthevo|R
3034|Rebirthfar|R
3025|RebirthGam|R
3008|RebirthGra|R
2936|Rebirthhap|R
3019|Rebirthint|R
2988|Rebirthman|R
5311|RebirthMen|R
6033|RebirthofK|R
3048|RebirthRel|R
5306|Rebirthsho|R
5318|Rebirthstr|R
3032|Rebirthstr|R
2975|Rebirthstr|R
5328|Rebirthswe|R
831|Reborn|R
1239|Rebornprot|R
5217|Recallingt|R
3796|recessiono|R
2328|recreation|R
4908|Redactor|R
812|RedAlert2|R
3689|Redcandyso|R
4727|redcutefoo|R
3837|Redemption|R
3187|RedHouse|R
4755|RedIronRoa|R
3576|redlotus|R
5008|RedLotusWi|R
3711|redpacketf|R
5572|redstone|R
5729|RED⑨|R
4601|Referstomu|R
3155|Refiner|R
853|RefiningPi|R
6674|reform|R
5129|ReformandO|R
5549|RegalinBla|R
5922|Regardless|R
3233|Regent|R
3835|Regression|R
1563|Regressor|R
3832|Regret|R
5412|Rehabilita|R
3859|Reiki|R
1765|ReikiRecov|R
1054|Reikyrecov|R
4017|Reimuer|R
162|Reincarnat|R
3438|reincarnat|R
1399|reincarnat|R
4356|Reincarnat|R
1737|reincarnat|R
1444|Reincarnat|R
1028|Reincarnat|R
913|Reincarnat|R
770|Reincarnat|R
523|Reincarnat|R
467|Reincarnat|R
415|Reincarnat|R
3228|rejoice|R
6188|rejoiceine|R
4446|Rejoiceint|R
6463|relatives|R
6341|Relax|R
1761|relaxed|R
6581|release|R
706|Religions|R
1057|ReligiousO|R
923|ReligousOr|R
3572|Remarriage|R
6622|Remember|R
5928|Rememberto|R
4640|rememberto|R
4235|Rengucuisi|R
4876|Repeat|R
5027|RepeatJiAi|R
545|Reporters|R
6260|Republicof|R
1701|Researcher|R
6797|resentment|R
2400|Residencen|R
2887|Resident Evil|R
1034|ResolutePr|R
4657|respectfor|R
635|Restaurant|R
2290|Restaurant|R
390|Resurrection|R
2701|Resurrection|R
5630|Returning from Another World|R
695|Returning from Another World|R
3236|Returnofth|R
5378|Returnofth|R
3042|Returnofth|R
5778|Returntent|R
1139|Returntoth|R
1487|Reunion|R
6191|Reunionaft|R
6326|Reunionaft|R
225|Revenge|R
5345|revengeLov|R
6286|Revengeont|R
5131|Reversal|R
3390|Reverse|R
378|Reverse Harem|R
571|Reverse Rape|R
614|ReverseRpe|R
2050|reversesmo|R
3256|reversewea|R
5325|reversewea|R
3080|reversewea|R
740|Reversible Couple|R
6311|ReviewBiog|R
6545|revolution|R
5748|Rhapsodyof|R
5250|Rhein-Life|R
4850|ricebath|R
5102|ricestar|R
6662|Riceweevil|R
1051|Rich to Poor|R
743|Rich to Poor|R
3454|richandbea|R
910|RichCharac|R
3715|Richestman|R
2510|richeveryy|R
1388|Richfamily|R
1144|RichMC|R
3395|richpeople|R
875|RichProtag|R
6400|Richsecond|R
5975|rideapiggy|R
1821|Rideawhale|R
6063|Rideawhale|R
5537|Ridethewin|R
3493|ridethewin|R
4860|ridicule|R
3744|ridiculous|R
630|Righteous Protagonist|R
1593|RimuruTemp|R
1792|RinYueqing|R
3604|riot|R
5220|RipplesofD|R
3437|RiseofGras|R
687|Rivalry|R
5161|rivercruis|R
2011|riversande|R
6267|Riversandl|R
4970|RoadtoAwak|R
6641|robot|R
5156|rockblosso|R
3720|rockfox|R
3924|Rococo|R
5623|rodeaway|R
4504|Roger18|R
3457|Rollover|R
768|Romance|R
3833|RomanceFan|R
6327|Romanceint|R
3489|RomanHolid|R
14|Romantic Subplot|R
6627|Romantic Subplot|R
711|Romantic Subplot|R
6215|RomanticCo|R
842|RomanticPr|R
6605|Rome|R
4766|RomeoTanak|R
4787|RongRong|R
1358|RookieProt|R
772|Roommates|R
2557|Roon|R
5167|Rossini|R
2627|Rotaryhotp|R
3781|rottenoran|R
3397|roughman|R
3131|RoyalBeast|R
6456|RoyalPalac|R
1957|RoyalSabur|R
35|Royalty|R
3354|Royalty|R
5|Rpe|R
115|RpeVictimB|R
6796|Ruins|R
6708|Ruleoflaw|R
6758|Rulethecou|R
5104|runaftercl|R
6776|Runaway|R
1841|runawayant|R
1809|runawaycit|R
4979|runawaydum|R
4217|runawaymid|R
4792|runawayrab|R
1244|Rune|R
3365|RuneMaster|R
3690|runningfis|R
6750|Runningwit|R
2241|Ruoshuithr|R
5415|ruotuosave|R
3696|rural|R
6743|Ruralarea|R
3922|Rushduck|R
1766|Russian|R
1435|ruthelessm|R
15|Ruthless Protagonist|R
1093|RuthlessMc|R
1406|rwby|R
2727|SacrificeX|S
3672|Sadakoiscu|S
622|Sadistic Characters|S
5677|Sadomasoch|S
1936|Sadreminde|S
2086|sadsadness|S
1840|sadsword|S
1064|SaikiK|S
1382|SaikiK.|S
1734|Sailing|S
4367|SaintPauli|S
1561|Saints|S
598|Saints|S
1082|SaintSeiya|S
5593|Saint丨Men|S
5518|SakeAsahi|S
5754|Sako|S
4066|Sakuracat|S
2639|Sakurajima|S
2207|SakuraMoon|S
6537|Sales|S
3292|Saltedfish|S
4874|Saltedfish|S
4233|Saltedfish|S
4074|saltedfish|S
2405|Saltedfish|S
5959|Saltedfish|S
5893|Saltedfish|S
5852|Saltedfish|S
5811|SaltedFish|S
5794|saltedfish|S
4818|Saltedfish|S
4723|saltedfish|S
3857|saltedfish|S
2685|SaltedFish|S
2299|SaltedFish|S
1851|SaltedFish|S
1089|SaltedFish|S
3314|Saltyandsw|S
3986|saltyfox|S
3846|Salvation|S
4167|sama|S
1170|SameSexMar|S
1025|Samurai|S
4938|SancheonHo|S
5209|sanctifica|S
2116|sandrivere|S
6142|Sandsculpt|S
3197|Sanguanzhe|S
2401|SanmitheGr|S
5215|SanyueFeng|S
3810|SaraDouble|S
3420|Satire|S
5645|saturdaymo|S
5348|Sauce|S
4450|Sauerkraut|S
6729|Savage|S
781|Saves|S
682|Saving the World|S
3822|Saygoodbye|S
4889|SCaja|S
1825|Scalesofth|S
5814|scarletmon|S
4660|ScarletMoo|S
5083|Scary|S
1742|schemeandc|S
1047|Schemes And Conspiracies|S
1460|Schemes And Conspiracies|S
405|Schemes And Conspiracies|S
1283|SchemingPr|S
5119|scholar|S
1267|School-lif|S
6381|Schoolflow|S
3615|schoolgras|S
6531|Schoolhear|S
746|SchoolLife|S
1678|SchoolSett|S
1003|Sci-Fantas|S
931|Sci-fi|S
1782|Science|S
1046|sciencefic|S
6161|Sciencefic|S
486|Scientists|S
1523|Scientists|S
4914|Scorpio|S
5193|Scorpionho|S
1971|Scourge|S
1140|SCP|S
5432|scrupulous|S
3114|scumbag|S
2981|scumbagReb|S
5262|scumfish|S
2308|scumteache|S
1116|SeaExplora|S
284|Sealed Power|S
1570|Sealed Power|S
3399|SealGod|S
5930|sea​​rou|S
5221|secludedci|S
99|Second Chance|S
1665|Second Chance|S
1410|Second Chance|S
4577|second-han|S
3816|Secondbatt|S
4366|Secondgive|S
2428|secondpira|S
266|Secret Crush|S
285|Secret Identity|S
652|Secret Organizations|S
1141|Secret Organizations|S
1021|Secret Relationship|S
1733|secretary|S
4105|SecretFrag|S
5066|Secretive Protagonist|S
552|Secretive Protagonist|S
3085|secretivec|S
2483|Secretobse|S
4974|secretolds|S
6319|SecretPrac|S
286|Secrets|S
6659|SecretTech|S
692|Sect Development|S
3547|Sect Development|S
6158|Sectbuildi|S
841|SectMaster|S
881|Sects|S
3320|Securitygu|S
732|Seduction|S
633|Seeing Things Other Humans Can't|S
6601|Seek|S
4216|Seelemywif|S
3116|seeyouagai|S
4208|Seeyouatth|S
6331|seizehome|S
3207|Self-disci|S
2372|self-disci|S
3306|self-impro|S
3548|SelfDiscip|S
254|Selfish Protagonist|S
558|Selfless Protagonist|S
5357|sellbloodf|S
4035|sellumbrel|S
5606|sellwine|S
500|Seme Protagonist|S
3373|Senbeiboy|S
2664|Sencha|S
5585|sendapacka|S
3318|Senior|S
970|Sentient Objects|S
1313|SentientSk|S
771|Sentimental Protagonist|S
1179|Sequel|S
550|Serial Killers|S
3389|SerpentKin|S
1817|ServantofZ|S
665|Servants|S
6740|Settingupa|S
691|Seven Deadly Sins|S
2209|Sevengener|S
1883|sevenpigeo|S
5929|SevenProfo|S
6371|Sevenstars|S
6269|Sevenyears|S
4314|severekaro|S
475|Sex Slaves|S
175|Sexual Abuse|S
748|Sexual Cultivation Technique|S
6663|shadow|S
2800|shadowfall|S
4022|shadowfire|S
2302|shadowghos|S
2929|Shadowless|S
1805|Shallowsea|S
203|Shameless Protagonist|S
4565|Shameless Protagonist|S
6108|ShamelessA|S
4813|ShangshanX|S
6454|ShangShu|S
3396|ShanHaiJin|S
4473|ShanhaiSpe|S
5639|Shaohuaisf|S
267|Shapeshifters|S
1100|Shapeshifters|S
3996|ShareHaiTs|S
296|Sharp-tongued Characters|S
1506|Shelter|S
2561|ShenhaoMec|S
2074|ShenhuoxoR|S
2543|ShenJin|S
6523|Shenlong|S
1993|ShenLuo|S
4386|ShenShen|S
4300|Sherlock|S
4465|shesaiditw|S
4764|Shiewillno|S
3244|Shijia|S
3367|Shiko|S
4427|ShiTianfen|S
4086|ShoesMenlu|S
6477|Shooter|S
559|Short Story|S
3175|shortforpa|S
493|Shota|S
556|Shotacon|S
595|Shoujo-Ai Subplot|S
955|ShoujoAi|S
1860|Shouldhand|S
530|Shounen-Ai Subplot|S
1533|Shounen-Ai Subplot|S
1719|shounenai|S
1467|ShouProtag|S
2888|Show-biz|S
108|Showbiz|S
3598|showdownfl|S
4613|ShowdownSa|S
2056|showstory|S
3529|ShreddedOn|S
4652|ShrimpBall|S
1820|shrimpinth|S
3148|Shuangjie|S
5312|ShuangjieD|S
1207|Shuangwen|S
1828|shudder|S
4287|Shura|S
3291|Shurachang|S
3284|Shushan|S
5577|Shuttlebus|S
4564|ShuyinFloa|S
2346|ShuYuChenX|S
482|Shy Characters|S
1094|Si-fi|S
46|Sibling Rivalry|S
750|Sibling&am|S
48|Siblings|S
448|Siblings Not Related by Blood|S
3861|sickleredr|S
3323|Sickly Characters|S
600|Sickly Characters|S
3531|sifeizhai|S
1294|Sign In|S
934|Sign-in|S
1242|Sign-InChe|S
4438|Signboardm|S
1331|SigninChec|S
2371|signinsalt|S
5663|SiheyuanDa|S
2276|SiheyuanDe|S
2175|Siheyuanfl|S
2246|SiheyuanGo|S
4448|Siheyuanpi|S
4162|Sijiu|S
2341|Silencehim|S
5423|silentauth|S
3787|Silentcare|S
2059|silentkill|S
1909|sillycatse|S
2363|SillyColum|S
5145|SillyTeres|S
3776|sillywhite|S
2807|silver|S
5178|silverbigs|S
3483|silvercold|S
4540|Silverhair|S
3667|Simmel|S
4743|Simon|S
6652|simple|S
2382|Simpleone|S
5648|simpletwo|S
4706|SimpleXiaZ|S
1646|Simulation|S
1172|Simulator|S
6527|sin|S
187|Singers|S
1770|Singers|S
6618|single|S
6340|Single Female Lead|S
503|Single Parent|S
1569|SingleHero|S
5469|singlemons|S
4753|singlepush|S
2865|singlesalt|S
4414|sink|S
6090|SirBirefel|S
5003|Siriuslook|S
1726|Siscon|S
709|Sister Complex|S
3358|Sisterandb|S
2553|sistercook|S
2379|sisterisbe|S
4724|SisterLuo|S
3184|SisterYu|S
4090|SituQingfe|S
1913|six-twochi|S
6026|Sixcauseso|S
5586|sixchiefs|S
4055|Sixi|S
4796|SixImmorta|S
5609|sixlittlef|S
2449|SixPathsof|S
3783|sixteenmir|S
4516|sixteennig|S
3871|sixthousan|S
2052|Sixty-six|S
3440|SkeletonSo|S
403|Skill Assimilation|S
508|Skill Books|S
572|Skill Creation|S
1353|SkillSteal|S
2322|SkinButler|S
6607|Sky|S
4112|skybird|S
4352|skycity|S
4226|SkyFeather|S
4962|SkyKilling|S
4036|SkyMender|S
979|Skyrim|S
4527|Skyshadowm|S
3805|SkyStealin|S
3713|slackerstu|S
5589|slagfly|S
4903|Slagwritin|S
3135|Slap|S
1566|SlapstickC|S
5313|Slapstrong|S
6552|Slaughter|S
1463|Slave|S
730|Slave Harem|S
540|Slave Protagonist|S
287|Slaves|S
828|SlaveSyste|S
6644|SlayingDem|S
6633|SlaytheDem|S
4847|sleepingbi|S
5521|sleepingra|S
2006|sleepingsa|S
2471|sleeplesst|S
1969|sleepslate|S
4664|sleepyanim|S
1259|Slice-of-l|S
877|SliceofLif|S
3890|slightlyco|S
1270|SlightlySu|S
5576|Slimeatsun|S
487|Slow Growth at Start|S
144|Slow Romance|S
3825|slow-movin|S
1011|slow-roman|S
1009|SlowCultiv|S
1481|SlowLife|S
4910|slowlytwis|S
4337|Slvery|S
4734|smallblade|S
5982|Smallcardd|S
3592|Smalldogs|S
5162|smallhalft|S
2552|Smallmushr|S
1900|smallninel|S
5978|SmallRibs|S
5107|smallself|S
3990|smalltempl|S
4814|smallten|S
513|Smart Couple|S
3557|Smart Couple|S
937|SmartMC|S
1215|smartprota|S
3646|SmelltheFo|S
4931|smellylitt|S
4106|smilecool|S
6038|Smokeandra|S
2644|Smokebambo|S
1798|SmokeCloud|S
1790|smokeinthe|S
5268|SMPZ|S
975|Smut|S
6700|Sniper|S
2038|snorkeling|S
3471|Snow|S
5442|Snowballfi|S
4394|snowcherry|S
5937|snowfall|S
4295|snowinthec|S
4833|snowmanbef|S
5618|snowmoonco|S
4466|SnowRoy|S
4037|so-and-soa|S
4075|soarupbyda|S
511|Soccer|S
755|Social Outcasts|S
6511|socialite|S
6508|society|S
2750|softorange|S
6525|Softrice|S
3308|softricefl|S
3425|SoftSci-fi|S
3840|Softyander|S
4043|SoIsay|S
5797|soisthewin|S
455|Soldiers|S
6651|Soldiers|S
4198|Solitary|S
3243|Solitarype|S
6166|Son-in-law|S
1461|Son-in-law|S
5695|Song|S
4165|SongHuangl|S
5861|SongofNort|S
2509|SongoftheG|S
2918|SonInLaw|S
4452|sonnet|S
1132|SonOfAGodP|S
6392|SonofDesti|S
3952|SonofMyria|S
3968|sonoftheqi|S
5883|SonofYuyin|S
2732|sopoor|S
4420|Sora|S
4411|soslack|S
404|Soul Power|S
2424|soulanddre|S
2415|SoulCelest|S
2244|SoulChef|S
3589|soulconver|S
2515|soulmemory|S
449|Souls|S
6597|SoulTransm|S
5654|SoulWorldR|S
989|SoundMagic|S
5556|SourceTaie|S
3854|southfire|S
2769|SouthKefei|S
5013|southmirro|S
5211|Southofthe|S
5515|Southwindo|S
4959|southwindt|S
917|Space|S
3178|Space-time|S
5694|space-time|S
3036|Space-time|S
2986|Space-time|S
6591|Spacebattl|S
807|SpaceOpera|S
547|Spaceship|S
4508|spacetimes|S
4757|SparklingP|S
721|Spatial Manipulation|S
578|Spear Wielder|S
353|Special Abilities|S
347|Special Abilities|S
1558|Special Abilities|S
1327|SpecialFor|S
940|SpecialLik|S
1162|SpecialLov|S
5051|specialpow|S
2359|specialwar|S
6719|speech|S
5174|Speechless|S
2692|speechless|S
2049|spendthewo|S
251|Spies|S
4304|Spike|S
654|Spirit Advisor|S
450|Spirit Users|S
1237|SpiritAnal|S
555|Spirits|S
4935|Spiritstri|S
1307|SpiritualQ|S
6411|Spiritualr|S
1219|SpiritualR|S
6574|Spiritworl|S
6767|spoiled|S
3588|spoiler|S
4177|spoilevery|S
6565|Spoof|S
3570|spookygame|S
992|Sports|S
993|SportsBask|S
3706|Sportscomp|S
4024|sportsgeni|S
4371|spring|S
6632|spy|S
6241|SpyAgent|S
3186|Spywar|S
5809|squirrelth|S
4625|ssangrydra|S
4725|St.LingYi|S
2506|stablefort|S
4149|stallion|S
2884|Stand User|S
5130|Stand-alon|S
1302|Star Wars|S
1433|Star Wars|S
1120|Starcraft|S
2376|stardarkni|S
5371|stareather|S
2667|starfish|S
3533|starlessni|S
4895|starnightf|S
3325|Startabusi|S
6697|Startingfr|S
5859|startingze|S
2258|startofthe|S
2121|startwriti|S
6624|statue|S
1813|Stayupalln|S
3903|stayupnigh|S
4867|stealingme|S
5116|Stealtheop|S
3559|steamponk|S
896|Steampunk|S
1626|Stepmother|S
1862|Sterile|S
5986|sterlingsi|S
2462|stevec|S
2482|StewedChic|S
5272|StewedRice|S
4308|stickfilia|S
6361|stimulate|S
2343|StinkBeanS|S
5033|Stir-Fried|S
3911|Stir-fried|S
188|Stockholm Syndrome|S
6536|Stockholm Syndrome|S
6586|stockmarke|S
729|Stoic Characters|S
2493|Stomachhur|S
2512|stonemored|S
2799|stopatfirs|S
4507|stopfighti|S
5765|stopsleepi|S
322|Store Owner|S
5806|StormyMoon|S
4434|stormyolds|S
5117|storytelle|S
643|Straight Seme|S
438|Straight Uke|S
3286|StraightAs|S
4470|Straightfo|S
3203|straightma|S
2893|straightma|S
2528|Straightme|S
3211|stranger|S
5904|Strangerss|S
150|Strategic Battles|S
451|Strategist|S
3109|Strategy|S
6307|StrategyFl|S
4381|strawshoes|S
911|Streamer|S
2762|streamerbl|S
3130|streamofhe|S
3241|Streamwith|S
371|Strength-based Social Hierarchy|S
4266|StrideinCh|S
5277|string|S
6788|Strive|S
1271|Strong|S
30|Strong Love Interests|S
1224|Strong Love Interests|S
118|Strong to Stronger|S
6201|strongandm|S
1324|StrongBack|S
3766|strongbun|S
1380|StrongCoup|S
4255|strongesta|S
6698|StrongestF|S
1520|StrongestP|S
3102|strongfema|S
861|StrongFema|S
5339|strongfema|S
5331|strongfema|S
3062|strongfema|S
3059|strongfema|S
3057|strongfema|S
3043|strongfema|S
3033|strongfema|S
2985|strongfema|S
2958|strongfema|S
2954|strongfema|S
1747|strongfema|S
1200|StrongFema|S
306|Strongfrom|S
873|Strongfrom|S
889|StrongMC|S
1065|StrongOpFe|S
915|StrongPowe|S
1212|StrongProt|S
3347|strongstre|S
862|Strongsubo|S
838|StrongSubo|S
4349|strongwoma|S
6396|StrongWome|S
3326|struggle|S
565|Stubborn Protagonist|S
5108|Stubbornan|S
3208|Student|S
365|Student-Teacher Relationship|S
2358|StudentUni|S
2020|stupidfox|S
4402|subjugatio|S
1760|submissive|S
6248|SUBSCRIPTI|S
6636|substance|S
3567|substitute|S
6431|success|S
4454|successoro|S
681|Succubus|S
551|Sudden Strength Gain|S
660|Sudden Wealth|S
4517|suddenlyit|S
4999|SuFengqian|S
5376|Sufferingp|S
3876|sugarpoem|S
3374|Sugary|S
3392|SuiandTang|S
1774|suicidalpr|S
775|Suicides|S
4372|summer|S
4629|summerjoke|S
2574|summernow|S
5355|summerrain|S
4828|summerseaf|S
1889|summertree|S
1888|summertrip|S
803|summon|S
602|Summoned Hero|S
938|Summoner|S
315|Summoning Magic|S
3156|Summoningf|S
1475|Summons|S
4702|SuMuQiuxue|S
6658|Sunday|S
1869|sundaysun|S
4534|SunflowerF|S
6442|sunlight|S
4782|SunnyPiggy|S
6048|sunset|S
3476|sunsetmoon|S
3901|sunsetnear|S
2755|sunsetover|S
3252|SuperA|S
5067|SuperAbili|S
4006|superdarkd|S
2852|Superfire|S
3753|supergodfi|S
2014|SuperGodGr|S
2849|SuperGodNo|S
1130|SuperHeroe|S
3011|Superman|S
6028|Superman7|S
6490|Supernatur|S
820|Supernatur|S
2385|Supernatur|S
5584|supernice1|S
2731|supernovab|S
2273|SuperPiran|S
360|Superpower|S
1265|Superpower|S
5281|superround|S
839|SuperSemin|S
1147|Superstar|S
1243|SuperTechn|S
3602|supplier|S
6189|Supporting|S
5682|Supporting|S
5400|Supporting|S
1524|Supportive|S
4554|supportthe|S
6226|SupremeFlo|S
5698|supremekin|S
3640|SupremeStr|S
5243|sure|S
5251|SurfProsec|S
100|Survival|S
514|Survival Game|S
3344|Survivalch|S
6457|survive|S
1892|SuShaoqing|S
4745|SushiKingB|S
1213|Suspense|S
3363|Suspensefl|S
3345|Suspensefu|S
6256|SuspenseMy|S
2383|SuWei|S
1878|SuYechen|S
4229|SuYuyu|S
2252|SuZiyouyou|S
5383|SuzuharaYu|S
1339|Swallowed Star|S
2670|swearnotto|S
1158|Sweet|S
5681|sweetandco|S
2261|Sweetandso|S
6261|sweetartic|S
5688|sweetheart|S
1836|sweetjelly|S
5086|Sweetlove|S
3105|sweetpet|S
1488|sweetroman|S
5591|SweetSoyMi|S
929|SweetText|S
3563|sweetwife|S
948|SweetYaoi|S
2686|Swimmingfi|S
2733|SwingingDe|S
288|Sword And Magic|S
325|Sword Wielder|S
1320|SwordArtOn|S
1852|Swordblood|S
2579|Swordgod|S
1898|SwordImmor|S
3280|swordrepai|S
2617|swordrepai|S
5464|Swordsheep|S
793|Swordsman|S
2229|Sword丨Lea|S
1581|SxFriends|S
116|SxualAbuse|S
1501|Sysetm|S
119|System|S
31|SystemAdmi|S
865|SystemAdmi|S
1644|SystemFlow|S
3040|systemflow|S
3023|systemflow|S
3015|systemflow|S
2983|systemflow|S
2979|systemflow|S
3734|systemmale|S
2281|SystemNo.3|S
1240|systemowne|S
1468|SystemTran|S
1330|SystemTran|S
518|TableTenni|T
5934|TachibanaM|T
5417|TaibaiJun1|T
6602|TaiChi|T
4676|TaihoZwei|T
1713|Tailsman|T
2455|Takeaplane|T
3434|takehome|T
2633|takeoffboy|T
2421|takeoverth|T
2172|takestock|T
586|Talent|T
3398|Talentedgi|T
1314|Talents|T
1521|TalentShow|T
1175|Talismans|T
5562|talkingtig|T
4789|tallpoorha|T
3107|TangDynast|T
2941|TangDynast|T
4391|TangerineT|T
1855|TangJichen|T
2220|TangShaoqi|T
2843|TangThirty|T
1472|Taoist|T
3113|Taoistprie|T
1628|Tasker|T
4896|TataTam|T
1929|TaurenIron|T
5985|TaurenWarr|T
3905|Taurus|T
5807|TCOCChrysa|T
3731|teacher-st|T
5905|TeacherDap|T
1348|TeacherDis|T
5866|TeacherHua|T
5052|teachermal|T
1349|TeacherMC|T
664|Teachers|T
252|Teachers|T
5372|tealcan&am|T
101|Teamwork|T
1351|Teamwork|T
488|Technological Gap|T
6790|Technological Gap|T
3288|technology|T
1121|Technology|T
961|Technology|T
6227|Technology|T
3348|Technology|T
1967|Technology|T
847|Technology|T
2107|TeckTyrann|T
2442|Teemotofly|T
2784|TeenageXia|T
1949|TempleThir|T
4108|ten-cutmad|T
2164|TenCommand|T
3943|Tenconsecu|T
6592|tenderness|T
519|Tennis|T
3878|tenrabbits|T
1594|Tensura|T
5249|tentaclemu|T
1020|Tentacles|T
2620|TenThousan|T
1939|Tenthousan|T
3921|TenYearsof|T
658|Terminal Illness|T
6304|TernaryMag|T
3342|Terracenea|T
1725|Territory Management|T
1329|TerritoryC|T
5068|Terrorists|T
767|Terrorists|T
1683|ThaiNovel|T
5011|Thanksgivi|T
4115|Thankyou|T
2563|Thankyoufo|T
5944|ThatMing|T
6542|thatpower|T
4433|TheAdventu|T
2259|Theancesto|T
6781|TheArtofWa|T
2419|Theashesar|T
1672|TheAsteris|T
5574|TheBeginni|T
3514|Thebestbra|T
2024|Thebigdevi|T
2016|Thebiggest|T
5492|Thebloodco|T
4592|Thebluesta|T
4403|Thebrillia|T
2475|Thecatisgo|T
6093|Thecatwhos|T
5636|TheChaosOr|T
4530|TheDailyLi|T
3580|thedayisco|T
5075|TheDevil|T
5430|theendofth|T
3975|TheEndofWo|T
3469|theevening|T
1426|theevernon|T
3898|Thefirstli|T
4445|thefishint|T
5920|Thefishkin|T
2871|Thefishmar|T
5226|Thefiveele|T
1808|Theflowero|T
3210|TheFourthC|T
1668|TheGamer|T
5539|Theghostre|T
3467|Thegloryof|T
2671|Thegloryof|T
2161|TheGodfath|T
1977|thegodofde|T
3625|Thegodoffa|T
1854|TheGospelo|T
3828|TheGreatDe|T
3287|theInterne|T
4882|Theirstory|T
6104|Thejourney|T
4102|thejudge|T
5488|Thekingask|T
3741|Thelastday|T
1920|Thelightof|T
2747|Thelistdep|T
2375|Thelistisi|T
4285|TheLonelyM|T
4181|Thelong-te|T
6308|TheLordGod|T
5074|TheMainCha|T
6530|themall|T
6353|theman|T
1225|TheManInTh|T
4829|Themorning|T
3584|Themysteri|T
2062|Thenewbact|T
2115|Theoceando|T
5735|Theoldboyw|T
2350|Theoldfive|T
3856|Theoldmani|T
4082|theothersh|T
6671|ThePathofM|T
6699|ThePathtoG|T
5832|Theplayofg|T
2537|Thepowerof|T
6132|Theprideof|T
6092|Theprovinc|T
2300|Thequeenis|T
6077|Therainisf|T
3998|TherealMr.|T
2143|therearefi|T
5575|Therearewh|T
6003|Thereisabu|T
5196|Thereisana|T
3500|Thereisfir|T
3543|ThereisnoN|T
5246|Thereisnos|T
6720|Thereturno|T
4971|Therunaway|T
6748|TheSageofM|T
3213|thescienti|T
3486|Theseahasn|T
3473|theseventh|T
5076|Thestronga|T
2105|Thestronge|T
1807|Thesunsett|T
5869|Theswordsw|T
4917|Thetasteof|T
1872|TheThreeKi|T
2841|Thetopofth|T
2303|Thetruegod|T
4851|Thetwothor|T
4824|Thevoiceof|T
2758|Thewayofth|T
6021|thewholewo|T
6039|Thewindblo|T
2075|thewindisb|T
5752|TheWizardS|T
2205|Theworld&a|T
4548|Theworldis|T
3520|Theworldis|T
4602|Theworldof|T
5838|theworldwi|T
3630|Thief|T
420|Thieves|T
4136|thinkcaref|T
2186|Thinkingof|T
6785|ThirdPrinc|T
4405|thirteen|T
5871|thirteenth|T
2323|Thirty-two|T
5142|Thirtycatt|T
3982|Thisconten|T
4845|thisisatru|T
2768|Thisissure|T
4759|Thismanisn|T
5955|Thiswaterm|T
2034|thisyear|T
5210|Thosewhowa|T
6243|ThoughtDi|T
4899|ThousandMo|T
4621|ThousandSh|T
5163|thousandso|T
2498|Thousandso|T
2399|ThousandTe|T
4700|thousandti|T
1356|Three Kingdoms|T
5693|Three Kingdoms|T
2935|Three Kingdoms|T
1912|Three-flav|T
3679|threeandfo|T
4567|threeclear|T
1856|Threedaysa|T
3786|threedaysf|T
4776|threedayst|T
2712|ThreeDotIn|T
5717|Threehundr|T
2198|threelittl|T
2503|ThreeLives|T
2072|ThreeLives|T
5995|Threepiece|T
3360|Threerelig|T
1042|Threesome|T
4092|threestick|T
2381|threeteeth|T
5419|ThreeThous|T
5151|threethous|T
3885|threethree|T
5239|ThreeTower|T
4107|Threeways|T
6044|Threeyolks|T
1950|ThreshingG|T
476|Thriller|T
6768|thrilling|T
4080|Throughthe|T
3691|ThugLuFeng|T
5289|thunderand|T
1981|Thunderous|T
1785|Tianbang78|T
5197|Tianbangbi|T
6087|TianbangCh|T
3371|TianbangDi|T
4041|TianbangFa|T
2741|Tianbanggr|T
2603|TianbangHu|T
2222|Tianbangol|T
6051|TianbangOt|T
2148|Tianbangth|T
4004|TianbangTo|T
2311|TianbangYa|T
4067|TianjiCour|T
6532|Tianlong|T
5504|TianNaixin|T
4040|TianrenCit|T
3709|Tianshi|T
2338|Tianshitak|T
3383|TianTingwe|T
4054|Tiantong|T
3507|TianyanShe|T
2306|TianYiding|T
5010|TianYixian|T
5769|tigerqueen|T
5225|tigerroar|T
3991|TigerSkinM|T
2520|Tigerteeth|T
4451|tigertiger|T
4991|Tiggerlove|T
702|Time Loop|T
672|Time Manipulation|T
777|Time Paradox|T
410|Time Skip|T
199|Time Travel|T
6752|Time-space|T
1940|Time-Trave|T
6173|timeandspa|T
1499|TimeandSpa|T
897|TimeandSpa|T
3336|timegate|T
5987|Timeissile|T
2560|TimeKingJO|T
3834|Timelimit|T
6736|Timeportal|T
463|Timid Protagonist|T
1884|TingFengZh|T
753|Titans|T
4801|toast|T
2187|tobacco|T
2699|Today&0|T
2716|Toilet|T
3794|toiletlepr|T
1446|Tokyo|T
1739|TokyoGhoul|T
4388|tomatofish|T
5499|TomatoUme|T
466|Tomboyish Female Lead|T
3978|TombRaider|T
2444|TombRaider|T
2433|TombRaider|T
2344|TombRaider|T
2213|TombRaider|T
6496|Tombraidin|T
4492|tomorrowwh|T
1896|tomorrowwi|T
2012|ToneMasaya|T
4926|Tongsheng|T
4491|Tongzi|T
5567|tonightrai|T
6060|Tooold|T
4485|toothinpig|T
1655|TopMC|T
2740|TopoftheCl|T
2103|TopoftheCl|T
2023|TopoftheCl|T
2420|TopoftheFo|T
3260|Topstream|T
1336|Toriko|T
6057|Tornadodes|T
728|Torture|T
4048|touchyou|T
6717|tough|T
3142|Toughgirl|T
6430|Toughguy|T
2662|towashthed|T
1177|TowerDefen|T
3610|trackandfi|T
863|Trade|T
3100|TradeWar|T
6314|Traditiona|T
887|Tragedy|T
140|Tragic Past|T
1601|Tramsmigra|T
852|Tranformer|T
6384|Transformation Ability|T
5686|Transformation Ability|T
109|Transformation Ability|T
4123|Transforme|T
1436|transmigat|T
32|Transmigration|T
1512|Transmigration|T
1098|Transmigration|T
1209|Transmigration|T
6346|Transmigration|T
1420|Transmigration|T
1119|Transmigration|T
1112|Transmigration|T
1048|Transmigration|T
968|Transmigration|T
525|Transplanted Memories|T
790|Transporte|T
554|Transporte|T
464|Transporte|T
372|Transporte|T
1299|TransportI|T
1231|Transportt|T
348|Trap|T
4353|travel|T
1571|Traveling|T
6115|Travelinga|T
1075|TravelingT|T
1625|traveller|T
6134|Travelthro|T
901|Traverse|T
3635|TreasureCh|T
1238|TreasureHu|T
964|TreasureHu|T
942|TreasureHu|T
3823|treefool|T
2809|treeofenli|T
6543|Trial|T
465|Tribal Society|T
3157|trickery|T
3075|trickery1V|T
2970|trickeryin|T
5335|trickerySl|T
452|Trickster|T
1552|Trnasmigra|T
3092|Troubledti|T
5349|TroubledTi|T
3054|Troubledti|T
3052|Troubledti|T
2534|TroubledWo|T
6216|TRPG|T
3189|Trueandfal|T
2915|TrueorFake|T
6718|TrueQi|T
2452|TrumanLive|T
5264|TsingYiLao|T
2138|TsukibaAki|T
349|Tsundere|T
4334|Tsundere|T
1723|TsundereLo|T
2464|Tsunderesc|T
801|Tsuru|T
3534|tumbler|T
6615|Turningthe|T
5943|Turnonairc|T
5561|Turnthecir|T
3937|Turtle|T
4750|turtlelike|T
6250|Tutor|T
4392|Tutuwantst|T
3852|twelvemove|T
2380|TwentyFame|T
1964|twilight|T
2775|twilightdr|T
1850|Twilightis|T
4011|twilightmy|T
1176|Twinbabies|T
2764|twingods|T
196|Twins|T
2645|Twistbroth|T
499|Twisted Personality|T
5385|TwistedChe|T
3678|two|T
6138|Two-dimens|T
4116|Two-dimens|T
2612|Two-dimens|T
2427|Two-dimens|T
2373|Two-dimens|T
3115|two-waycru|T
3321|two-wayred|T
3488|TwoChildre|T
6144|Twodimensi|T
6010|Twohorsesa|T
5704|TwoJinSuia|T
2714|Twopeopleb|T
2673|Twopoundso|T
3536|Twotwothre|T
4648|twotwoyell|T
1595|TypeMoon|T
1762|Tyrant|T
5578|Uchihaswor|U
3448|Ugly|U
739|Ugly Protagonist|U
483|Ugly to Beautiful|U
6040|Uglyface|U
6722|UglyGirl|U
4760|Ultimatein|U
6302|Ultramanin|U
5658|UltramanJu|U
1935|UltramanPo|U
2048|unbearable|U
6390|unbelievab|U
5669|Uncertainw|U
3593|Uncle|U
5386|UncleArche|U
4435|UncleLiter|U
5544|UncleLiuHu|U
4296|UncleMario|U
5404|unclemerea|U
141|Unconditional Love|U
4345|Undead Protagonist|U
2124|undeadfish|U
2214|Undead丨Kn|U
2850|Undefeated|U
3328|Undercover|U
6673|Underdog&a|U
580|Underestimated Protagonist|U
6726|undergroun|U
2702|underlolic|U
2431|undersilve|U
2833|understate|U
4843|understood|U
3537|underthera|U
4616|underthesn|U
3743|underthest|U
6689|underworld|U
5360|UnderYeYuc|U
1801|Undocument|U
4574|Unexpected|U
1395|unexpected|U
5381|unfinished|U
6265|UniformLov|U
2824|Unintentio|U
3845|Unique|U
323|Unique Cultivation Technique|U
6580|Uniquethin|U
735|UniqueWeap|U
751|UniqueWeap|U
6278|Unittext|U
4293|Universale|U
6362|University|U
6363|University|U
6695|University|U
2517|unknown|U
2422|UnknownTao|U
1833|Unknowntea|U
1530|Unlimited Flow|U
6350|Unlimited Flow|U
2844|Unlimitedc|U
3955|Unlimiteds|U
432|Unlucky Protagonist|U
4119|Unlucky Protagonist|U
5078|Unprincipl|U
456|Unreliable Narrator|U
5948|Unremarkab|U
561|Unrequited Love|U
3472|UnrulyConf|U
4098|unyielding|U
3951|Updatewith|U
3132|upgrade|U
3204|upgradeflo|U
6368|UpgradeStr|U
2184|Upsetting|U
350|Urban|U
1874|UrbanDatan|U
3601|urbanimmor|U
893|UrbanLife|U
2505|UrbanMilit|U
6157|Urbanroman|U
6187|UrbanRoman|U
2256|urbanshark|U
2210|urbanstar|U
6257|UrbanStran|U
2846|Urbanyearn|U
5907|urbanyoung|U
1727|Urbanyouth|U
6587|USA|U
6432|Useless|U
6631|value|V
2504|vampiredri|V
16|Vampires|V
995|Vampires|V
3232|Vanves|V
3274|Variety|V
1645|VarietySho|V
4210|VenerableP|V
4039|VenusSoul|V
1222|Versatile Mage|V
3989|veryhappy|V
5402|veryobsess|V
4957|verypurean|V
3933|verysleepy|V
1504|Vest|V
6654|veteran|V
6617|Vibrato|V
5230|Vicissitud|V
5819|Victoria|V
924|VictorianE|V
5080|Videogame|V
4339|videogames|V
3362|videostrea|V
4183|Vientiane|V
1973|Viewofthec|V
3381|VikaBaka|V
3935|villageisv|V
5031|VillagerB|V
538|Villainess Noble Girls|V
698|Villainess Noble Girls|V
1618|Villainess Noble Girls|V
1323|VillainEvi|V
1637|VillainPro|V
1548|Villains|V
1502|VillIain|V
3195|VinegarKin|V
4338|Violence|V
5980|violentthu|V
93|Virtual Reality|V
6599|virus|V
912|Vlogging|V
4826|Vodkaandmi|V
3224|Voice Actors|V
549|Voice Actors|V
1319|VoicePack|V
5463|VoidLinnos|V
4623|VoidStupid|V
5764|Wakeup|W
2297|Walkinthec|W
4658|walkonthee|W
2088|Wanderer|W
1963|wanderings|W
4513|WangDachen|W
2459|WangEr|W
5908|WangHuoyub|W
1845|WangJiu|W
3504|WangLin|W
2353|WangXiaomi|W
3779|WanliWanhu|W
5475|Wannianfen|W
5270|WanTsang|W
2859|wanttocome|W
2501|wanttoeatg|W
4952|Wanttoeatt|W
5540|wanttohold|W
4520|wanttolive|W
848|War|W
1187|War Records|W
3904|warboss|W
4360|Warcraft|W
6207|Warhammer|W
796|Warhammer4|W
3418|Warlock|W
792|Warlocks|W
6535|warlord|W
3216|Warm|W
4722|warmalittl|W
4251|warmaster|W
3447|Warmman|W
4472|warmmilkte|W
2606|warmtime|W
2906|WarofCivil|W
6534|WarringSta|W
3293|warrior|W
151|Wars|W
1572|Warship|W
696|WarsWeakto|W
4247|wastebaske|W
4020|wastedream|W
2453|wastefish|W
898|Wasteland|W
6185|wastestrea|W
6774|Wastewater|W
2167|WasteWoodA|W
3442|Wastewoodf|W
5594|Wastewoodn|W
3926|watchtoget|W
4502|waterdropr|W
3355|WaterMargi|W
5007|watermelon|W
4721|watermelon|W
2169|watermelon|W
3515|watermolec|W
5967|watertenta|W
2585|watertown|W
3485|waxypen|W
477|Weak Protagonist|W
17|Weak to Strong|W
5097|Weak to Strong|W
4614|weaklyacid|W
1325|WeaktoClan|W
1602|WealthChar|W
7|Wealthy Characters|W
1536|Wealthy Characters|W
4467|Wealthy Characters|W
1573|Wealthy Characters|W
5046|wealthyfam|W
1612|Wearabook|W
3147|wearback|W
1154|WearBook|W
5333|wearbooksy|W
1718|wearingabo|W
5369|weatapeach|W
1673|WebNovel|W
1043|WebnovelSp|W
6561|wedding|W
1002|WeektoStro|W
6320|WeirdGame|W
6135|Weirdstori|W
3826|WeiyangXun|W
6569|WeiZhen|W
2541|WenGuang|W
4880|WenrenJing|W
2546|WenXuanyu|W
4242|WenYue|W
765|Werebeasts|W
5061|Werewolf|W
1148|Werewolves|W
1387|WesternFan|W
2119|Westernrai|W
3382|WestwardJo|W
5181|what&03|W
4430|What&03|W
2028|What&03|W
5926|Whatareyou|W
5773|whatisyour|W
5835|Whattodoif|W
5157|Whattodowi|W
4294|Whenthedev|W
4707|WhentheJun|W
4748|WhenyourNP|W
6285|Whimsical|W
3453|White|W
1260|WhiteBunSe|W
3748|Whitecolla|W
4501|whiteconfe|W
5266|WhiteDevil|W
4701|whitefiref|W
5300|whitefox|W
3662|whitefoxfr|W
4778|whitegown|W
2349|Whitehorse|W
2249|whitekeybo|W
5002|whitelate|W
3749|whitelotus|W
3343|Whitemoonl|W
4904|whiterice|W
2798|whiteshirt|W
3573|Whitesnake|W
5925|Whitesparr|W
6303|Whitevineg|W
3839|Wholesome|W
2713|Whoringmak|W
3895|wife-chasi|W
2583|WifeistheD|W
5140|wildcatsus|W
5263|wildcrumbs|W
4777|Wilde|W
6571|wilderness|W
884|Wilderness|W
6702|Wilderness|W
6089|wilderness|W
5884|wildlove|W
5953|wildradish|W
5550|Will-o&|W
2447|willowcand|W
3465|Willowleav|W
3723|windandclo|W
5459|windandfor|W
2616|windandmap|W
4728|WindandSno|W
4632|Windandwea|W
3930|windandwhe|W
4176|windchime~|W
4783|winddance|W
4830|WindMeteor|W
1932|WindSpirit|W
5801|windstopsn|W
3824|windtobebu|W
5110|windup|W
5642|WindWhispe|W
5751|windy|W
6012|windyblack|W
5293|wingedgras|W
2294|Winningthe|W
4150|winter|W
4744|WinterandS|W
5876|winterbird|W
4547|Winterfall|W
4911|wipeandpic|W
3108|Wisdom|W
1819|wishardtow|W
562|Wishes|W
3750|Witch|W
647|Witches|W
2139|witchfan|W
2413|witheredpr|W
5169|witheredsh|W
3521|WithShehbu|W
4939|wittylittl|W
316|Wizards|W
902|Wizards|W
3301|wizardstre|W
6058|WolfTotem|W
6376|woman|W
6148|women&0|W
3983|WongTingLi|W
4091|woodbig|W
3916|Woodbrothe|W
5599|woodenswor|W
5126|Working|W
3271|Workplace|W
3571|workplaceb|W
5974|world|W
33|World Hopping|W
332|World Travel|W
679|World Tree|W
867|World-hopp|W
1337|WorldEmpir|W
945|WorldHopin|W
4737|worldofphi|W
1703|WorldofWar|W
5063|Worlds|W
1495|WorldWar2|W
6420|Worshipmon|W
2894|WOW|W
6619|Wretched|W
5141|Writeabook|W
4977|writebighe|W
5718|writebookq|W
4820|WriteBooks|W
1837|writeonlyz|W
406|Writers|W
872|Writers|W
5833|WriterUHae|W
5615|Writingfoo|W
2429|Wuhutookof|W
4073|WuhuWuhu|W
626|Wuxia|W
5947|Wuxiabuysf|W
1849|Wuxicheng|W
3730|WW2|W
4310|wxya|W
4981|XiaJiBanxi|X
4027|XiaJiEight|X
4379|XiangziYan|X
3173|Xianjun|X
4227|XianmengXi|X
255|Xianxia|X
6133|XianxiaCul|X
5874|XianYushan|X
3446|Xianzun|X
4973|Xiaobaicry|X
5439|Xiaobuisno|X
4747|Xiaofei|X
4627|Xiaohubuys|X
5737|XiaoJieJie|X
6119|XiaoLinWei|X
6054|Xiaomiisah|X
2648|XiaomiStar|X
4742|XiaoMo&|X
2529|Xiaonianbl|X
2621|XiaonianXu|X
6081|Xiaoqianhu|X
5535|Xiaoran|X
6423|Xiaosan|X
4669|XiaoshanQi|X
4679|XiaoTangon|X
2858|Xiaothreey|X
2836|XiaoxiangP|X
5529|XiaoXiao|X
1944|Xiaoxin|X
5224|Xiaoyuhast|X
4558|Xiaozhi|X
4887|XiaTing|X
3912|Xiawholove|X
4894|XiaXiaolan|X
4684|XiaXiaXia|X
2519|XieDaoheng|X
4257|Xier|X
3387|Xijing|X
6626|Xingtian|X
5380|Xinjia|X
3353|Xiuwaihuih|X
3133|Xiuxian|X
5198|Xiuxian&am|X
1848|XiuXiuXiuX|X
5781|Xizhilangc|X
5546|XL-423|X
3985|XNUMXDupda|X
539|Xuanhuan|X
3962|Xuansheng|X
4551|XuanyueQin|X
4279|XuanYuisea|X
2231|XuebaIII|X
2275|Xuebaisinv|X
2065|Xueqiunder|X
4521|XueshenSan|X
2247|Xufamilyel|X
2477|XuIintheTa|X
4515|XuShizi|X
5633|XuShiziqia|X
4437|XuYuanle|X
4161|YaeSakurai|Y
6043|Yahyfvs|Y
2279|Yakult|Y
3909|Yakumo|Y
3923|Yakumobloo|Y
4121|Yakumofami|Y
5882|Yakumowhit|Y
6473|Yama|Y
5625|Yamasquirr|Y
3229|Yancontrol|Y
5627|yandcrooke|Y
510|Yandere|Y
2071|YangXiaoA|Y
4311|YangXiaoli|Y
5352|YanQiuyu|Y
5259|YanyunYing|Y
446|Yaoi|Y
2864|Yaoyue|Y
5683|Yapi|Y
4726|yary|Y
5255|YawuZiyun|Y
2822|yearaftery|Y
2743|yearningfo|Y
2551|yearningfo|Y
2365|Yearningfo|Y
2230|yearningfo|Y
2193|Yearningfo|Y
2926|Yearningto|Y
4218|YeChengzho|Y
4762|YeFeiyu|Y
2680|YeGongzi|Y
2646|YeGucheng|Y
4151|YeGuxue|Y
5158|yellowleav|Y
1788|YellowSpri|Y
1829|YeluChengj|Y
2766|YeQianqiu|Y
6025|YeTingfeng|Y
4846|YeTong|Y
2286|YeXiaobai|Y
2928|YeYe|Y
4716|Yibai|Y
5976|Yibuchuckl|Y
5422|YichenSwor|Y
6143|yinandyang|Y
2274|Ying&03|Y
4600|Yinglili&a|Y
5629|YinGongziY|Y
4906|YingTianMo|Y
2029|YingXiaofe|Y
1924|YinLiisins|Y
1983|Yongchuang|Y
3881|yonorth|Y
4690|Yoooooooom|Y
3505|Youalsowan|Y
5356|youareatra|Y
5612|Youarelike|Y
1899|youaretoow|Y
4672|Youkaishan|Y
5091|Young|Y
747|Younger Brothers|Y
769|Younger Love Interests|Y
563|Younger Sisters|Y
6667|Younggeniu|Y
6083|Younghero|Y
4326|younglovei|Y
6589|Youngmaste|Y
5234|YoungMaste|Y
2757|YoungMaste|Y
2669|YoungMaste|Y
6650|youngnoble|Y
5732|Youofthesk|Y
4361|Yourpupils|Y
894|Youth|Y
6598|YouthCampu|Y
6274|YouthComic|Y
5152|YouthLittl|Y
5153|youwholove|Y
5854|YouZhu|Y
5039|youzi|Y
5299|yoyo|Y
6202|Yu-Gi-Oh!|Y
1085|Yu-Gi-Oh!|Y
5696|YuanandMin|Y
5652|YuanXiwu|Y
3938|Yuanyiunde|Y
6075|Yuanyuzhou|Y
2282|YuboTiandi|Y
4084|YuDaoan|Y
4094|Yueguhua|Y
4550|YuFengqian|Y
1263|Yugioh|Y
3773|Yujielonga|Y
3780|YuMingYins|Y
3583|Yunding丨P|Y
4915|YunJiangdo|Y
2233|Yunmu|Y
6008|Yunshan|Y
6073|YunXiaoluo|Y
2839|YunZhongju|Y
3544|YunZimo|Y
840|Yuri|Y
4714|YuShiyu|Y
4656|YushuangYS|Y
5015|YuSu|Y
5354|Yutang|Y
2524|YuTsingYi|Y
2136|YuXiaoqi|Y
2687|YuYuyu|Y
805|z-man|Z
4246|Zanfran|Z
4968|ZanpakutoK|Z
5787|Zcraft|Z
1076|Zerg|Z
1104|Zergs|Z
3754|Zerocharge|Z
3827|zeroclothe|Z
6005|zerooverfl|Z
1442|zfighters|Z
2653|ZhangErgou|Z
2569|ZhangFeiin|Z
3756|ZhangGaoqi|Z
4276|Zhanginfro|Z
2548|ZhangJuli|Z
4703|ZhangLuo|Z
6165|Zhangmenli|Z
3669|ZhangShuan|Z
2335|ZhangTianb|Z
6604|ZhangYang|Z
5190|ZhaNiu|Z
4327|ZhaoSisi|Z
5498|ZhaoWenwub|Z
3295|Zhengde|Z
3391|Zhenguan|Z
4985|ZhiLingInk|Z
2697|zhishen|Z
4477|Zhiyuan|Z
5611|ZhouJijiu|Z
4234|ZhuangShis|Z
2851|ZhuDabald|Z
4563|Zhuge|Z
2576|ZhugeDali&|Z
2165|ZhugeIrona|Z
2584|Zhugeiscra|Z
5361|ZhuqiuSanj|Z
6146|Zhutianliu|Z
6416|ZhuXian|Z
2123|ZhuZhiyue|Z
3811|ZiandIaren|Z
2706|Zippo|Z
1903|ZiXuanXuan|Z
5927|Ziyingisno|Z
5005|Zofi|Z
2257|zombiefish|Z
2145|ZombieGod|Z
1577|ZombieQuee|Z
102|Zombies|Z
918|Zombies|Z
3377|ZombieSumo|Z
3412|Zongmen|Z
920|Zoo|Z
2150|Zuge|Z
2266|Zulongstil|Z
5791|ZuoJinghon|Z
2676|ZuwuGonggo|Z
5728|☆Crazy→M|C
5851|一条小段段|Y
5890|丑颜|C
5945|东晨|D
5214|丫大|Y
6347|丹药|D
6616|乙女向|Y
5834|云怅|Y
6219|互穿|H
6342|人生|R
1873|仕辰|S
6360|仙侠|X
6334|仵作|Z
6550|会战|H
6309|作精|Z
4028|你的答案|N
6372|兄弟|X
6349|入赘|R
6474|兵王|B
6239|兽世|S
6428|军婚|J
5520|北八|B
3873|半弦|B
6178|双洁|S
6196|反穿|F
6419|变异|B
6706|史记|S
6471|名媛|M
6316|吞噬|T
6443|商界|S
6449|团宠|T
6009|夜独|Y
6032|天律|T
6378|契约|Q
6175|女强|N
3212|女神|N
3172|妖精|Y
6391|娱乐|Y
5123|婚姻|H
6177|嫡女|D
6751|宅女|Z
6254|宅斗|Z
3124|宋朝|S
6469|家庭|J
3460|家族|J
6245|富民|F
6755|小妾|X
2203|小封|X
6455|希望|X
6731|庶女|S
6111|开凡|K
6351|异世|Y
6798|异性|Y
5901|影|Y
5720|往月|W
6611|御龙|Y
6479|恐怖|K
6383|恶霸|E
6377|恶鬼|E
6446|感情|G
2057|慕阳|M
6459|成魔|C
6232|护花|H
6441|报仇|B
6310|捕快|B
3777|教授|J
6359|文明|W
6252|文野|W
6666|斗气|D
6262|日常|R
5939|晓墨|X
6453|朝堂|C
5522|木其|M
6369|杀伐果断|S
6485|杀戮|S
6481|校草|X
2361|森罗|S
6745|武林|W
6665|武魂|W
3312|氪金|J
6312|水浒|S
6715|求生之路|Q
6424|汉末|H
5800|汪叽|W
6027|沙酱|S
6197|清穿|Q
2838|清裁|Q
5192|温桑|W
6116|焕焕|H
6344|狐妖|H
5816|王晏|W
3393|王者荣耀|W
6682|生化|S
6364|盗墓|D
3279|直播|Z
6448|社会|S
3222|神话|S
3103|空间|K
6223|第四天灾|D
6486|算计|S
6283|糙汉|C
6472|系统流|X
6192|群穿|Q
6335|聊斋|L
6123|肆灵|S
2821|萌图|M
6480|萌妹|M
6447|虐渣|N
6328|蛮荒|M
5514|蝉眠|C
6793|血族|X
6167|西幻|X
6794|言情|Y
6357|诛仙|Z
1904|谢邀|X
5989|财女|C
6180|贵女|G
6343|赘婿|Z
5963|越泽|Y
6386|转生|Z
6370|轻鬆|Q
6179|追妻|Z
6436|选秀|X
6313|遮天|Z
2182|酣歌|H
5895|醉咏|Z
5923|醉猫|Z
3101|金融|J
2093|铁帅|T
6692|镇山|Z
6352|阵法|Z
2924|零充|L
3714|非洲|F
4863|风水|F
1831|饕牛|N
-- END_TAG_INDEX
]==]

local ALL_TAGS = {}
local TAGS_BY_ID = {}
do
    local seen = {}
    for line in TAG_SEARCH_INDEX:gmatch("[^\r\n]+") do
        if string.sub(line, 1, 2) ~= "--" then
            local id, label, letter = string.match(line, "^([^|]+)|([^|]+)|([^|]*)$")
            if not id then
                id, label = string.match(line, "^([^|]+)|([^|]+)$")
            end
            if id and label and not seen[id] then
                seen[id] = true
                local lower = string.lower(label)
                if not letter or letter == "" then
                    letter = string.upper(string.sub(label, 1, 1))
                end
                local tag = {
                    id     = id,
                    label  = label,
                    lower  = lower,
                    flat   = lower:gsub("%s+", ""),
                    letter = letter,
                }
                ALL_TAGS[#ALL_TAGS + 1] = tag
                TAGS_BY_ID[id] = tag
            end
        end
    end
end

-- Resolve a free-text Tag Search field into a deduplicated list of tag ids.
-- Semantics (mirrors the site's own tag browsing + the wtrlab tag search):
--   • Tokens are split on comma / semicolon; spaces stay INSIDE tokens so
--     multi-word phrases work ("weak to strong" == "weaktostrong").
--   • Per token, resolution order:
--       1. exact name match, case- AND space-insensitive ("male prot" →
--          MaleProtagonist); several site tags share a squashed name —
--          every exact match is included;
--       2. numeric token — a verbatim tag id (validated);
--       3. "keyword*" wildcard — includes ALL substring matches at once;
--       4. ANY substring match — a partial keyword INCLUDES every tag
--          containing it: the search "shows everything as a result";
--       5. multi-word token with no phrase match → per-word fallback.
--   • A token with no match at all raises a clear error.
--   • letter: ""/"all"/nil = all letters, else a single "A".."Z" — scopes
--     the whole resolution (mirrors the /browsetags/ letter grouping).
local MAX_UNION_TAGS = 12

function tagSearchResolve(text, letter)
    if not text or text == "" then return {} end
    local scopeAll = (not letter) or letter == "" or string.lower(letter) == "all"
    local scopeLetter = nil
    if not scopeAll then scopeLetter = string.upper(letter) end

    local seen, out = {}, {}

    local function scoped(t)
        return (scopeLetter == nil) or t.letter == scopeLetter
    end

    -- every tag whose flattened name contains `flatToken` (plain substring)
    local function substringMatches(flatToken)
        local matches = {}
        for _, t in ipairs(ALL_TAGS) do
            if scoped(t) and string.find(t.flat, flatToken, 1, true) then
                matches[#matches + 1] = t
            end
        end
        return matches
    end

    local function addTag(t)
        if not seen[t.id] then
            seen[t.id] = true
            out[#out + 1] = t.id
        end
    end

    local function formatMatches(matches, maxN)
        local names = {}
        for i = 1, math.min(#matches, maxN) do
            names[#names + 1] = matches[i].label .. " (#" .. matches[i].id .. ")"
        end
        local s = table.concat(names, ", ")
        if #matches > maxN then
            s = s .. ", …and " .. (#matches - maxN) .. " more"
        end
        return s
    end

    local function resolveToken(token)
        local lowerToken = string.lower(token)
        local flatToken  = lowerToken:gsub("%s+", "")

        -- 1) exact (space-insensitive) name match
        local exact = {}
        for _, t in ipairs(ALL_TAGS) do
            if scoped(t) and t.flat == flatToken then exact[#exact + 1] = t end
        end
        if #exact > 0 then
            for _, t in ipairs(exact) do addTag(t) end
            return
        end

        -- 2) verbatim numeric tag id
        if string.match(token, "^%d+$") then
            local t = TAGS_BY_ID[token]
            if t then
                if scoped(t) then addTag(t) return end
                error("tag id " .. token .. " does not start with letter " .. tostring(scopeLetter) .. ".")
            end
            error("no tag with id " .. token .. " on wuxiabox.com.")
        end

        -- 3) trailing-* wildcard: every substring match at once
        if string.sub(token, -1) == "*" then
            local stem = flatToken:sub(1, -2)
            if stem == "" then return end
            local matches = substringMatches(stem)
            if #matches == 0 then
                error("no tag name contains '" .. stem .. "'." ..
                    (scopeLetter ~= nil and (" (scoped to letter " .. scopeLetter .. ")") or ""))
            end
            for _, t in ipairs(matches) do addTag(t) end
            return
        end

        -- 4) substring: INCLUDE EVERY MATCH
        local matches = substringMatches(flatToken)
        if #matches > 0 then
            for _, t in ipairs(matches) do addTag(t) end
            return
        end

        -- 5) multi-word fallback: resolve word by word
        if string.find(token, "%s") then
            for word in token:gmatch("%S+") do resolveToken(word) end
            return
        end

        error("no tag name contains '" .. token .. "'." ..
            (scopeLetter ~= nil and (" (scoped to letter " .. scopeLetter .. ")") or ""))
    end

    for token in string.gmatch(text, "[^,;]+") do
        token = string.gsub(token, "^%s+", "")
        token = string.gsub(token, "%s+$", "")
        if token ~= "" then resolveToken(token) end
    end

    if #out > MAX_UNION_TAGS then
        local names = {}
        for _, id in ipairs(out) do
            names[#names + 1] = TAGS_BY_ID[id] and TAGS_BY_ID[id].label or id
        end
        error("Tag Search matched " .. #out .. " tags (" ..
            table.concat(names, ", ", 1, MAX_UNION_TAGS) .. ", …). " ..
            "wuxiabox.com browses ONE tag listing at a time, so the plugin merges " ..
            "them into " .. #out .. " parallel requests per result page — too many. " ..
            "Type a more specific keyword or an exact tag name.")
    end

    return out
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CATALOG / SEARCH / FILTERS
-- ═══════════════════════════════════════════════════════════════════════════

-- Parse .novel-item cards — shared by catalog list, tag listings, search
-- results and the updates page. Card anatomy (verified live):
--   <li class="novel-item"><a href="/novel/{slug}.html" title="{Title}">
--     … img.lazy[data-src] … <h4 class="novel-title">{Title}</h4> …
-- `toNovelUrl` rewrites the updates-page variant (links point at the
-- LATEST CHAPTER, /novel/{slug}_{n}.html) back to the novel page.
local function parseNovelCards(body, toNovelUrl)
    local items = {}
    local seen = {}
    for _, card in ipairs(html_select(body, "li.novel-item")) do
        local a = html_select_first(card.html, "a[href]")
        if a then
            local url = absUrl(a.href)
            if toNovelUrl then
                url = string.gsub(url, "_(%d+)%.html$", ".html")
            end
            local title = string_clean(a.title)
            if title == "" then
                local t = html_select_first(card.html, "h4.novel-title, h5.novel-title")
                if t then title = string_clean(t.text) end
            end
            if url ~= "" and title ~= "" and not seen[url] then
                seen[url] = true
                local cover = html_attr(card.html, "img[data-src]", "data-src")
                if cover == "" then cover = html_attr(card.html, "img[src]", "src") end
                items[#items + 1] = { title = title, url = url, cover = absUrl(cover) }
            end
        end
    end
    return items
end

-- hasNext via "link to the NEXT page exists in the pager" — the generic
-- scheme for every listing on this site (numbered pages + > / >> links).
-- needle is the literal URL fragment identifying the next page.
-- listTotal: when the pager carries a grand-total marker
-- (<ul class="pagination"><a title="总数"><b>N</b>), a page-full math
-- fallback covers pagers whose link format shifts.
local function hasNextByLink(body, needle)
    if string.find(body, needle, 1, true) then return true end
    return false
end

local function listTotal(body)
    return tonumber(string.match(body, '<ul class="pagination">.-<b>(%d+)</b>'))
end

-- ── Catalog (default browse: Most Popular) ──────────────────────────────────

function getCatalogList(index)
    local page = index
    local url = SITE .. "/list/all/all-onclick-" .. tostring(page) .. ".html"
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseNovelCards(r.body, false)
    local hasNext = hasNextByLink(r.body, "/list/all/all-onclick-" .. tostring(page + 1) .. ".html")
    return { items = items, hasNext = hasNext }
end

-- ── Search (EmpireCMS POST form + manual redirect following) ────────────────

-- searchid cache per query for the lifetime of one engine run
local _searchIdByQuery = {}

local function extractSearchId(body)
    return string.match(body, "searchid=(%d+)")
end

-- Follow up to 3 manual redirect hops (NoveLA's OkHttp client does not
-- follow redirects for plugin calls by default).
local function followRedirects(r)
    local hops = 0
    while hops < 3 do
        local code = tonumber(r.code) or 0
        if code ~= 301 and code ~= 302 and code ~= 303 and code ~= 307 and code ~= 308 then
            return r
        end
        local loc = headerFirst(r.headers, "location")
        if not loc then return r end
        r = http_get(absUrl(loc))
        hops = hops + 1
    end
    return r
end

-- POST the site's own search form; on failure fall back to the GET
-- searchget=1 variant. Returns the RESULT page body (or nil).
local function runSearch(query)
    local form = "show=title&tempid=1&tbname=news&keyboard=" .. url_encode(query)
    local r = http_post(SITE .. "/e/search/index.php", form, {
        headers = {
            ["Referer"] = SITE .. "/search.html",
            ["Origin"]  = SITE,
            ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        }
    })
    r = followRedirects(r)
    if r.success and extractSearchId(r.body) then return r.body end

    -- Fallback: EmpireCMS GET search (verified live: redirects to the
    -- same /e/search/result?searchid=N page).
    local getUrl = SITE .. "/e/search/?searchget=1&keyboard=" .. url_encode(query) ..
        "&show=title&tbname=news&tempid=1"
    local g = http_get(getUrl, { headers = { ["Referer"] = SITE .. "/search.html" } })
    g = followRedirects(g)
    if g.success and extractSearchId(g.body) then return g.body end

    return nil
end

function getCatalogSearch(index, query)
    if index == 0 then
        local body = runSearch(query)
        if not body then return { items = {}, hasNext = false } end
        _searchIdByQuery[query] = extractSearchId(body)
        local items = parseNovelCards(body, false)
        local hasNext = hasNextByLink(body, "page=1&searchid=")
        local total = listTotal(body)
        if total and 1 * 20 < total then hasNext = true end
        return { items = items, hasNext = hasNext }
    end

    local sid = _searchIdByQuery[query]
    if not sid then
        -- engine asked for a later page without page 0 in this run
        local body = runSearch(query)
        if not body then return { items = {}, hasNext = false } end
        sid = extractSearchId(body)
        _searchIdByQuery[query] = sid
    end
    if not sid then return { items = {}, hasNext = false } end

    local url = SITE .. "/e/search/result/index.php?page=" .. tostring(index) ..
        "&searchid=" .. sid
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseNovelCards(r.body, false)
    local hasNext = hasNextByLink(r.body, "page=" .. tostring(index + 1) .. "&searchid=")
    local total = listTotal(r.body)
    if total and (index + 1) * 20 < total then hasNext = true end
    return { items = items, hasNext = hasNext }
end

-- ── Filters ─────────────────────────────────────────────────────────────────

local CATEGORIES = {
    { value = "all",                  label = "All" },
    { value = "action",               label = "Action" },
    { value = "adventure",            label = "Adventure" },
    { value = "chinese",              label = "Chinese" },
    { value = "comedy",               label = "Comedy" },
    { value = "contemporary-romance", label = "Contemporary Romance" },
    { value = "drama",                label = "Drama" },
    { value = "eastern-fantasy",      label = "Eastern Fantasy" },
    { value = "erciyuan",             label = "Erciyuan" },
    { value = "faloo",                label = "Faloo" },
    { value = "fan-fiction",          label = "Fan-Fiction" },
    { value = "fantasy",              label = "Fantasy" },
    { value = "fantasy-romance",      label = "Fantasy Romance" },
    { value = "game",                 label = "Game" },
    { value = "gender-bender",        label = "Gender Bender" },
    { value = "harem",                label = "Harem" },
    { value = "hentai",               label = "Hentai" },
    { value = "historical",           label = "Historical" },
    { value = "horror",               label = "Horror" },
    { value = "isekai",               label = "Isekai" },
    { value = "japanese",             label = "Japanese" },
    { value = "josei",                label = "Josei" },
    { value = "lolicon",              label = "Lolicon" },
    { value = "magic",                label = "Magic" },
    { value = "magical-realism",      label = "Magical Realism" },
    { value = "martial-arts",         label = "Martial Arts" },
    { value = "mecha",                label = "Mecha" },
    { value = "military",             label = "Military" },
    { value = "mystery",              label = "Mystery" },
    { value = "official_circles",     label = "Official Circles" },
    { value = "psychological",        label = "Psychological" },
    { value = "romance",              label = "Romance" },
    { value = "school-life",          label = "School Life" },
    { value = "sci-fi",               label = "Sci-fi" },
    { value = "science_fiction",      label = "Science Fiction" },
    { value = "seinen",               label = "Seinen" },
    { value = "shoujo",               label = "Shoujo" },
    { value = "shoujo-ai",            label = "Shoujo Ai" },
    { value = "shounen",              label = "Shounen" },
    { value = "shounen-ai",           label = "Shounen Ai" },
    { value = "slice-of-life",        label = "Slice of Life" },
    { value = "sports",               label = "Sports" },
    { value = "supernatural",         label = "Supernatural" },
    { value = "suspense_thriller",    label = "Suspense Thriller" },
    { value = "tragedy",              label = "Tragedy" },
    { value = "travel_through_time",  label = "Travel Through Time" },
    { value = "two-dimensional",      label = "Two-dimensional" },
    { value = "urban",                label = "Urban" },
    { value = "urban-life",           label = "Urban Life" },
    { value = "video-games",          label = "Video Games" },
    { value = "virtual-reality",      label = "Virtual Reality" },
    { value = "wuxia",                label = "Wuxia" },
    { value = "wuxia_xianxia",        label = "Wuxia Xianxia" },
    { value = "xianxia",              label = "Xianxia" },
    { value = "xuanhuan",             label = "Xuanhuan" },
    { value = "yaoi",                 label = "Yaoi" },
    { value = "yuri",                 label = "Yuri" },
}

local TAG_LETTERS = {
    { value = "",  label = "All" },
    { value = "A", label = "A" }, { value = "B", label = "B" },
    { value = "C", label = "C" }, { value = "D", label = "D" },
    { value = "E", label = "E" }, { value = "F", label = "F" },
    { value = "G", label = "G" }, { value = "H", label = "H" },
    { value = "I", label = "I" }, { value = "J", label = "J" },
    { value = "K", label = "K" }, { value = "L", label = "L" },
    { value = "M", label = "M" }, { value = "N", label = "N" },
    { value = "O", label = "O" }, { value = "P", label = "P" },
    { value = "Q", label = "Q" }, { value = "R", label = "R" },
    { value = "S", label = "S" }, { value = "T", label = "T" },
    { value = "U", label = "U" }, { value = "V", label = "V" },
    { value = "W", label = "W" }, { value = "X", label = "X" },
    { value = "Y", label = "Y" }, { value = "Z", label = "Z" },
}

function getFilterList()
    return {
        {
            type         = "select",
            key          = "browse",
            label        = "Browse Mode",
            defaultValue = "catalog",
            options = {
                { value = "catalog", label = "Categories (filters below)" },
                { value = "updates", label = "Recently Updated" },
            }
        },
        {
            type         = "select",
            key          = "category",
            label        = "Category",
            defaultValue = "all",
            options      = CATEGORIES,
        },
        {
            type         = "select",
            key          = "status",
            label        = "Status",
            defaultValue = "all",
            options = {
                { value = "all",       label = "All" },
                { value = "Completed", label = "Completed" },
                { value = "Ongoing",   label = "Ongoing" },
            }
        },
        {
            type         = "select",
            key          = "sort",
            label        = "Sort By",
            defaultValue = "newstime",
            options = {
                { value = "newstime",   label = "Newest Added" },
                { value = "lastdotime", label = "Last Updated" },
                { value = "onclick",    label = "Most Viewed" },
            }
        },
        {
            type         = "text",
            key          = "tag_search",
            label        = "Tag Search (keyword — shows every matching tag)",
            defaultValue = "",
        },
        {
            type         = "select",
            key          = "tag_letter",
            label        = "Tag Search Category (first letter)",
            defaultValue = "",
            options      = TAG_LETTERS,
        },
    }
end

-- Tag listing URL for result page `index` (0-based).
--   page 0 → /tags/{id}-0.html            (500 items on one page)
--   page N → /e/tags/index.php?page=N&tagid={id}&line=500&tempid=9
local function tagListingUrl(tagId, index)
    if index <= 0 then
        return SITE .. "/tags/" .. tagId .. "-0.html"
    end
    return SITE .. "/e/tags/index.php?page=" .. tostring(index) ..
        "&tagid=" .. tagId .. "&line=500&tempid=9"
end

-- Browse ONE tag listing at page `index`. hasNext: next-page link in the
-- pager, with a grand-total fallback (500 items per tag page).
local function browseTag(tagId, index)
    local url = tagListingUrl(tagId, index)
    browsePacing(400)
    local r = http_get(url)
    if not r.success then return {}, false end
    local items = parseNovelCards(r.body, false)
    local hasNext = hasNextByLink(r.body, "page=" .. tostring(index + 1) .. "&tagid=" .. tagId)
    local total = listTotal(r.body)
    if total and (index + 1) * 500 < total then hasNext = true end
    return items, hasNext
end

-- UNION browse: merge the listings of several tags ("everything as search
-- result"), deduplicated by novel URL. One paced request per tag.
local function browseTagUnion(tagIds, index)
    local merged, seen = {}, {}
    local anyNext = false
    for _, tagId in ipairs(tagIds) do
        local items, hasNext = browseTag(tagId, index)
        if hasNext then anyNext = true end
        for _, it in ipairs(items) do
            if not seen[it.url] then
                seen[it.url] = true
                merged[#merged + 1] = it
            end
        end
    end
    return merged, anyNext
end

function getCatalogFiltered(index, filters)
    local browse    = filters["browse"]    or "catalog"
    local category  = filters["category"]  or "all"
    local status    = filters["status"]    or "all"
    local sort      = filters["sort"]      or "newstime"
    local tagQuery  = filters["tag_search"] or ""
    local tagLetter = filters["tag_letter"] or ""

    -- ── Tag Search: takes priority (the site cannot combine a tag listing
    -- with category/status/sort — documented in the plugin header).
    if tagQuery ~= "" then
        local ok, tagIds = pcall(tagSearchResolve, tagQuery, tagLetter)
        if not ok then error(tostring(tagIds)) end
        if #tagIds == 0 then return { items = {}, hasNext = false } end
        local items, hasNext = browseTagUnion(tagIds, index)
        return { items = items, hasNext = hasNext }
    end

    -- ── Updates mode (ignores category/status/sort)
    if browse == "updates" then
        local url
        if index <= 0 then
            url = SITE .. "/updates/"
        else
            url = SITE .. "/updates/" .. tostring(index) .. ".html"
        end
        local r = http_get(url)
        if not r.success then return { items = {}, hasNext = false } end
        -- cards link to the LATEST chapter → rewrite to the novel page
        local items = parseNovelCards(r.body, true)
        local hasNext = hasNextByLink(r.body, "/updates/" .. tostring(index + 1) .. ".html")
        return { items = items, hasNext = hasNext }
    end

    -- ── Categories mode
    local url = SITE .. "/list/" .. url_encode(category) .. "/" ..
        url_encode(status) .. "-" .. url_encode(sort) .. "-" .. tostring(index) .. ".html"
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseNovelCards(r.body, false)
    local hasNext = hasNextByLink(r.body, "-" .. tostring(index + 1) .. ".html")
    return { items = items, hasNext = hasNext }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOK DETAILS  (all share the novel page via fetchPage — one HTTP request)
-- ═══════════════════════════════════════════════════════════════════════════

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h1.novel-title")
    if el then
        local t = string_clean(el.text)
        if t ~= "" then return t end
    end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    -- figure.cover is the novel-page shape; ".cover img" kept from base
    -- v1.0.1 as a fallback for variant markups.
    local cover = html_attr(body, "figure.cover img", "data-src")
    if cover == "" then cover = html_attr(body, "figure.cover img", "src") end
    if cover == "" then cover = html_attr(body, ".cover img", "data-src") end
    if cover == "" then cover = html_attr(body, ".cover img", "src") end
    if cover ~= "" then return absUrl(cover) end
    return nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    -- Selector preference kept from base v1.0.1, but the site renders
    -- <p class="description"> EMPTY on novel pages (and "" is truthy in
    -- Lua, so v1.0.1 returned empty descriptions) — fall through to the
    -- real synopsis block when the preferred node has no text.
    local el = html_select_first(body, "p.description")
    local text = ""
    if el then text = string_trim(html_text(el.html)) end
    if text == "" then
        el = html_select_first(body, ".summary .content")
        if el then text = string_trim(html_text(el.html)) end
    end
    if text == "" then return nil end
    -- The site often prepends a bracketed tag-soup line
    -- ("[Farming + Relaxed Entertainment + Traveling]") — keep it, it is
    -- part of the site's own synopsis presentation.
    return text
end

-- Genres = the site's Categories chips + the novel's Tags chips (the tags
-- are shown with their FULL names here, unlike /browsetags/ listings).
function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres, seen = {}, {}
    for _, a in ipairs(html_select(body, ".categories a")) do
        local g = string_clean(a.text)
        if g ~= "" and not seen[g] then
            seen[g] = true
            genres[#genres + 1] = g
        end
    end
    return genres
end

-- Status from .header-stats: <span><strong>Completed</strong><small>Status</small></span>
function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, sp in ipairs(html_select(body, ".header-stats span")) do
        local small = html_select_first(sp.html, "small")
        if small and string.lower(string_clean(small.text)) == "status" then
            local strong = html_select_first(sp.html, "strong")
            if strong then
                local v = string_clean(strong.text)
                if v ~= "" then return v end
            end
        end
    end
    return nil
end

-- Last update = the date under the NEWEST chapter (the novel page shows the
-- OLDEST 100 chapters, so for long novels the newest chapter lives on the
-- LAST fy.php page; one extra lightweight fragment request, cached).
function getBookLastUpdate(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local slug = novelSlug(bookUrl)
    if not slug then return nil end

    local function lastTimeOf(htmlBody)
        local times = html_select(htmlBody, "ul.chapter-list time")
        if #times == 0 then return nil end
        local last = times[#times]
        return normalizeUpdateDate(string_clean(last.text))
    end

    -- highest fy.php page linked from the novel page's chapter pager
    local maxFy = 0
    for _, a in ipairs(html_select(body, "a[href]")) do
        local p = string.match(a.href or "", "/e/extend/fy%.php%?page=(%d+)&wjm=")
        if p then
            local n = tonumber(p) or 0
            if n > maxFy then maxFy = n end
        end
    end

    if maxFy > 0 then
        local fyUrl = SITE .. "/e/extend/fy.php?page=" .. tostring(maxFy) ..
            "&wjm=" .. url_encode(slug)
        local frag = fetchPage(fyUrl, FY_HEADERS)
        if frag then
            local d = lastTimeOf(frag)
            if d then return d end
        end
    end
    return lastTimeOf(body)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CHAPTER LIST  (parsePage — paginated, incremental updates)
--
--   engine page 1  → the novel page itself (chapters 1-100, ASCENDING)
--   engine page N  → /e/extend/fy.php?page={N-1}&wjm={slug} (100/page)
--   totalPages     → highest fy.php page linked in the pager + 1
-- The site serves old→new within every page and old pages first, exactly
-- the order the engine expects — no inversion needed.
-- ═══════════════════════════════════════════════════════════════════════════

local function parseChapterItems(body)
    local chapters = {}
    for _, a in ipairs(html_select(body, "ul.chapter-list li a[href]")) do
        local chUrl = absUrl(a.href)
        if chUrl ~= "" then
            local title = ""
            local strong = html_select_first(a.html, "strong.chapter-title")
            if strong then title = string_clean(strong.text) end
            if title == "" then title = string_clean(a.title) end
            if title == "" then
                local no = html_select_first(a.html, "span.chapter-no")
                if no then title = string_clean(no.text) end
            end
            if title == "" then
                local n = string.match(chUrl, "_(%d+)%.html$")
                if n then title = "Chapter " .. n end
            end
            chapters[#chapters + 1] = { title = title, url = chUrl }
        end
    end
    return chapters
end

local function detectTotalListPages(body)
    local maxFy = 0
    for _, a in ipairs(html_select(body, "a[href]")) do
        local p = string.match(a.href or "", "/e/extend/fy%.php%?page=(%d+)&wjm=")
        if p then
            local n = tonumber(p) or 0
            if n > maxFy then maxFy = n end
        end
    end
    return maxFy + 1
end

function parsePage(bookUrl, page)
    local slug = novelSlug(bookUrl)
    if not slug then return { chapters = {}, totalPages = 1 } end

    local body
    if page <= 1 then
        body = fetchPage(bookUrl)
    else
        browsePacing(350)
        body = fetchPage(SITE .. "/e/extend/fy.php?page=" .. tostring(page - 1) ..
            "&wjm=" .. url_encode(slug), FY_HEADERS)
    end
    if not body then return { chapters = {}, totalPages = 1 } end

    local chapters = parseChapterItems(body)
    local totalPages = detectTotalListPages(body)
    if #chapters == 0 and page > 1 then
        -- a fy page beyond the end: keep totalPages sane
        return { chapters = {}, totalPages = page - 1 > 0 and page - 1 or 1 }
    end
    return { chapters = chapters, totalPages = totalPages }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CHAPTER TEXT  (+ the "502 every ~2 chapters" self-healing path)
-- ═══════════════════════════════════════════════════════════════════════════

function getChapterText(html, url)
    -- Pacing floor between chapter requests (default 1500 ms; setting).
    chapterPacing()

    local body = html
    if isChapterErrorPage(body) then
        log_error("wuxiabox: error/interstitial page for " .. tostring(url) ..
            " — refetching with backoff")
        body = refetchChapterWithRetry(url)
    end
    if not body or isChapterErrorPage(body) then
        log_error("wuxiabox: chapter could not be loaded: " .. tostring(url))
        return ""
    end

    local cleaned = html_remove(body,
        "script", "style", "iframe", "ins",
        "div[align=center]", ".ads", ".advertisement",
        ".chapternav", ".recommends")

    local el = html_select_first(cleaned, "#chapter-article .chapter-content")
    if not el then el = html_select_first(cleaned, ".chapter-content") end
    if not el then return "" end

    local text = html_text(el.html)
    text = stripTitleEcho(text, body)
    text = applyStandardContentTransforms(text)
    -- Trailing author-note + end marker — kept from base v1.0.1.
    text = regex_replace(text, "(?s)\\s*\\([^)]*\\)\\s*\\(End of this chapter\\)\\s*$", "")
    text = regex_replace(text, "(?s)\\s*\\(End of this chapter\\)\\s*$", "")
    return string_trim(text)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════

function getSettingsSchema()
    return {
        {
            key     = PREF_RETRY,
            type    = "select",
            label   = "Chapter retries on 502 / error pages",
            current = tostring(getRetryCount()),
            options = {
                { value = "2", label = "2 attempts" },
                { value = "3", label = "3 attempts" },
                { value = "4", label = "4 attempts (recommended)" },
                { value = "5", label = "5 attempts" },
                { value = "6", label = "6 attempts" },
            }
        },
        {
            key     = PREF_PACE,
            type    = "select",
            label   = "Min gap between chapter requests (502 prevention)",
            current = tostring(getPaceMs()),
            options = {
                { value = "0",    label = "Off" },
                { value = "800",  label = "0.8 seconds" },
                { value = "1500", label = "1.5 seconds (recommended)" },
                { value = "2500", label = "2.5 seconds" },
                { value = "4000", label = "4 seconds" },
            }
        },
    }
end
