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

    -- Baca konfigurasi semasa dari config.json
    if fs.access(config_path) then
        local content = fs.readfile(config_path)
        if content then
            cfg = json.parse(content) or {}
        end
    end

    -- Mengendalikan tindakan butang
    if http.formvalue("action") == "reload" then
        -- Muat semula halaman
        http.redirect(luci.dispatcher.build_url("admin/services/sshws"))
        return
    elseif http.formvalue("action") == "save" then
        -- Update JSON fields dari form (borang)
        local newcfg = {
            mode = http.formvalue("mode") or "proxy",
            proxyHost = http.formvalue("proxyHost") or "",
            
            -- PENTING: Kekalkan proxyPort sebagai STRING ("80") untuk mengelakkan ralat Go unmarshal
            proxyPort = http.formvalue("proxyPort") or "80", 
            
            ssh = {
                host = http.formvalue("ssh_host") or "",
                -- port kekal sebagai nombor (integer)
                port = tonumber(http.formvalue("ssh_port")) or 22, 
                username = http.formvalue("ssh_username") or "",
                password = http.formvalue("ssh_password") or ""
            },
            httpPayload = http.formvalue("httpPayload") or "",
            -- connectionTimeout kekal sebagai nombor (integer)
            connectionTimeout = tonumber(http.formvalue("connectionTimeout")) or 30
        }
        
        -- Tulis konfigurasi baharu ke fail /root/config.json
        fs.writefile(config_path, json.stringify(newcfg, true))
        
        -- Paparkan mesej kejayaan
        luci.template.render("sshws", { cfg = newcfg, message = "✅ Konfigurasi disimpan ke /root/config.json" })
        return
        
    elseif http.formvalue("action") == "start" then
        -- Mulakan/Restart perkhidmatan sshws
        sys.call("/etc/init.d/sshws restart >/dev/null 2>&1 &")
        luci.template.render("sshws", { cfg = cfg, message = "🟢 SSHWS dimulakan" })
        return
        
    elseif http.formvalue("action") == "stop" then
        -- Hentikan perkhidmatan sshws
        sys.call("/etc/init.d/sshws stop >/dev/null 2>&1 &")
        luci.template.render("sshws", { cfg = cfg, message = "🔴 SSHWS dihentikan" })
        return
    end

    -- Paparkan borang konfigurasi
    luci.template.render("sshws", { cfg = cfg })
end