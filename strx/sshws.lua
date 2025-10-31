module("luci.controller.sshws", package.seeall)

function index()
    -- Daftarkan entri menu di bawah 'Services'
    entry({"admin", "services", "sshws"}, call("action_sshws"), _("SSHWS Tunnel"), 100).leaf = true
end

function action_sshws()
    local fs = require "nixio.fs"
    local json = require "luci.jsonc"
    local sys = require "luci.sys"
    local http = require "luci.http"

    local config_path = "/root/config.json"
    local cfg = {}
    local message = nil

    -- 1. Ambil mesej status dari URL (untuk PRG)
    local status_msg = http.formvalue("msg")
    if status_msg == "start_ok" then
        message = "🟢 SSHWS Started."
    elseif status_msg == "stop_ok" then
        message = "🔴 SSHWS Stopped."
    elseif status_msg == "save_ok" then
        message = "✅ Config Saved to /root/config.json"
    end

    -- 2. Baca konfigurasi semasa dari config.json
    if fs.access(config_path) then
        local content = fs.readfile(config_path)
        if content and content ~= "" then
            cfg = json.parse(content) or {}
        end
    end
    
    -- Pastikan struktur SSH wujud
    if not cfg.ssh then
        cfg.ssh = {}
    end
    
    -- 3. Dapatkan WAN IP dan ISP dari curl-ip.guide
    local cmd = "curl -s 'https://ip.guide?format=json'"
    local raw_data = sys.exec(cmd)
    
    local success, data = pcall(json.parse, raw_data)

    if success and type(data) == "table" then
        cfg.wan_ip = data.ip or "N/A"
        
        if data.network and data.network.autonomous_system then
            cfg.isp_name = data.network.autonomous_system.organization or "N/A"
        else
            cfg.isp_name = "N/A (Check network)"
        end
    else
        cfg.wan_ip = "Failed to fetch/parse IP."
        cfg.isp_name = "Check connectivity/libraries."
    end
    
    -- 4. Mengendalikan tindakan butang (POST)
    if http.formvalue("action") == "reload" then
        http.redirect(luci.dispatcher.build_url("admin/services/sshws"))
        return
        
    elseif http.formvalue("action") == "save" then
        local newcfg = {
            mode = http.formvalue("mode") or "proxy",
            proxyHost = http.formvalue("proxyHost") or "",
            proxyPort = http.formvalue("proxyPort") or "80", 
            
            ssh = {
                host = http.formvalue("ssh_host") or "",
                port = tonumber(http.formvalue("ssh_port")) or 22, 
                username = http.formvalue("ssh_username") or "",
                password = http.formvalue("ssh_password") or ""
            },
            httpPayload = http.formvalue("httpPayload") or "",
            connectionTimeout = tonumber(http.formvalue("connectionTimeout")) or 30
        }
        
        fs.writefile(config_path, json.stringify(newcfg))
        
        -- ⭐ PRG: Redirect ke URL dengan mesej status
        http.redirect(luci.dispatcher.build_url("admin/services/sshws") .. "?msg=save_ok")
        return
        
    elseif http.formvalue("action") == "start" then
        sys.call("/etc/init.d/sshws restart >/dev/null 2>&1 &")
        
        -- ⭐ PRG: Redirect ke URL dengan mesej status
        http.redirect(luci.dispatcher.build_url("admin/services/sshws") .. "?msg=start_ok")
        return
        
    elseif http.formvalue("action") == "stop" then
        sys.call("/etc/init.d/sshws stop >/dev/null 2>&1 &")
        
        -- ⭐ PRG: Redirect ke URL dengan mesej status
        http.redirect(luci.dispatcher.build_url("admin/services/sshws") .. "?msg=stop_ok")
        return
    end

    -- 5. Paparkan borang konfigurasi
    luci.template.render("sshws", { cfg = cfg, message = message })
end
