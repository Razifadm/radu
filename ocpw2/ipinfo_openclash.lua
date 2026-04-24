module("luci.controller.ipinfo_openclash", package.seeall)

function index()
    -- API ONLY
    entry({"openclash", "get_ip"}, call("get_ip")).leaf = true
    entry({"openclash", "ping_test"}, call("ping_test")).leaf = true
end

-- ======================
-- IP INFO API
-- ======================
function get_ip()
    local http = require "luci.http"

    local f = io.popen("curl -s --max-time 6 https://ip.guide 2>/dev/null")
    local r = f:read("*a")
    f:close()

    http.prepare_content("application/json")

    if not r or r == "" then
        http.write('{"error":true,"message":"no data"}')
        return
    end

    http.write(r)
end

-- ======================
-- REAL ROUTE LATENCY TEST
-- HTTP / HTTPS TEST, NOT ICMP
-- ======================
function ping_test()
    local http = require "luci.http"

    -- Ini lebih real daripada ping 1.1.1.1.
    -- generate_204 ringan dan sesuai untuk latency test.
    local test_url = "https://www.gstatic.com/generate_204"

    -- Ukur total HTTP time.
    -- Output curl hanya nombor saat, contoh:
    -- 0.128934
    local cmd = "curl -L -s -o /dev/null " ..
                "--connect-timeout 3 " ..
                "--max-time 6 " ..
                "-w '%{time_total}' " ..
                "'" .. test_url .. "' " ..
                "2>/dev/null"

    local f = io.popen(cmd)
    local r = f:read("*a")
    f:close()

    local seconds = tonumber(r or "")
    local ms = nil

    http.prepare_content("application/json")

    if seconds and seconds > 0 then
        ms = seconds * 1000

        http.write(string.format(
            '{"alive":true,"status":"online","method":"http_latency","target":"%s","ping":%.0f,"display":"%.0f ms"}',
            test_url,
            ms,
            ms
        ))
    else
        http.write(string.format(
            '{"alive":false,"status":"offline","method":"http_latency","target":"%s","ping":null,"display":"-"}',
            test_url
        ))
    end
end
