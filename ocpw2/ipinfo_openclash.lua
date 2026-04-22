module("luci.controller.ipinfo_openclash", package.seeall)

function index()

    -- API ONLY (NO UI PAGE)
    entry({"openclash","get_ip"}, call("get_ip")).leaf = true
    entry({"openclash","ping_test"}, call("ping_test")).leaf = true

end


-- ======================
-- IP INFO API
-- ======================
function get_ip()
    local http = require "luci.http"

    local f = io.popen("curl -s --max-time 3 https://ip.guide 2>/dev/null")
    local r = f:read("*a")
    f:close()

    http.prepare_content("application/json")

    if not r or r == "" then
        http.write('{"error":"no data"}')
        return
    end

    http.write(r)
end


-- ======================
-- REAL PING TEST (ICMP)
-- ======================
function ping_test()
    local http = require "luci.http"

    local f = io.popen("ping -c 1 -W 1 1.1.1.1 2>/dev/null | grep time=")
    local r = f:read("*a")
    f:close()

    local ms = string.match(r or "", "time=([%d%.]+)")

    http.prepare_content("application/json")

    if not ms then
        http.write('{"ping":0}')
    else
        http.write('{"ping":' .. ms .. '}')
    end
end
