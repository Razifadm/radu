module("luci.controller.pw2ip", package.seeall)

function index()
    entry({"pw2ip", "info"}, call("get_ip_info")).leaf = true
    entry({"pw2ip", "ping"}, call("ping_test")).leaf = true
end

function get_ip_info()
    local http = require "luci.http"
    
    local f = io.popen("curl -s --max-time 5 'https://ip.guide' 2>/dev/null")
    local r = f:read("*a")
    f:close()
    
    http.prepare_content("application/json")
    
    if not r or r == "" then
        http.write('{"error":"no data"}')
        return
    end
    
    http.write(r)
end

function ping_test()
    local http = require "luci.http"
    
    -- Use curl to measure REAL HTTP latency (bypasses ICMP redirection)
    -- This will go through passwall2 proxy and give realistic latency
    local cmd = [[
        curl -s -o /dev/null -w "%{time_total}" --max-time 10 https://www.google.com 2>/dev/null
    ]]
    
    local f = io.popen(cmd)
    local r = f:read("*a")
    f:close()
    
    -- Convert seconds to milliseconds
    local ms = nil
    if r and r ~= "" then
        local time_sec = tonumber(r)
        if time_sec then
            ms = math.floor(time_sec * 1000 + 0.5)
        end
    end
    
    -- Fallback to cloudflare
    if not ms or ms == 0 then
        cmd = [[
            curl -s -o /dev/null -w "%{time_total}" --max-time 10 https://www.cloudflare.com 2>/dev/null
        ]]
        f = io.popen(cmd)
        r = f:read("*a")
        f:close()
        if r and r ~= "" then
            local time_sec = tonumber(r)
            if time_sec then
                ms = math.floor(time_sec * 1000 + 0.5)
            end
        end
    end
    
    http.prepare_content("application/json")
    
    if not ms or ms == 0 then
        http.write('{"ping":0}')
    else
        http.write('{"ping":' .. ms .. '}')
    end
end
