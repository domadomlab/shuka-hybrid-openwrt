module("luci.controller.shuka_hybrid", package.seeall)

function index()
    entry({"admin", "services"}, firstchild(), _("Services"), 40).index = true
    entry({"admin", "services", "shuka"}, call("action_gui"), "Shuka VPN", 60)
    entry({"admin", "services", "shuka", "sync"}, call("action_sync"), nil).leaf = true
    entry({"admin", "services", "shuka", "data"}, call("action_data"), nil).leaf = true
    entry({"admin", "services", "shuka", "select"}, call("action_select"), nil).leaf = true
    entry({"admin", "services", "shuka", "force_ping"}, call("action_force_ping"), nil).leaf = true
    entry({"admin", "services", "shuka", "start"}, call("action_start"), nil).leaf = true
    entry({"admin", "services", "shuka", "stop"}, call("action_stop"), nil).leaf = true
    entry({"admin", "services", "shuka", "amnezia_upload"}, call("action_amnezia_upload"), nil).leaf = true
    entry({"admin", "services", "shuka", "clear_sub"}, call("action_clear_sub"), nil).leaf = true
    entry({"admin", "services", "shuka", "delete_amnezia"}, call("action_delete_amnezia"), nil).leaf = true
end

local function strip(s)
    if not s then return "" end
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

function action_sync()
    local url = luci.http.formvalue("url")
    if url then
        local f = io.open("/etc/sing-box/sub_url.txt", "w")
        f:write(url)
        f:close()
    end
    os.execute("/usr/bin/shuka_manager.py sync >/dev/null 2>&1 &")
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_clear_sub()
    os.execute("/usr/bin/shuka_manager.py clear_sub >/dev/null 2>&1 &")
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_amnezia_upload()
    local http = require "luci.http"
    local tmp = "/tmp/amnezia_upload.conf"
    local fp = io.open(tmp, "w")
    http.setfilehandler(function(m, c, e)
        if c then fp:write(c) end
        if e then fp:close() end
    end)
    http.formvalue("amneziadata")
    os.execute("/usr/bin/shuka_manager.py amnezia " .. tmp .. " >/dev/null 2>&1 &")
    http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end

function action_delete_amnezia()
    local tag = luci.http.formvalue("tag")
    if tag then
        os.execute("/usr/bin/shuka_manager.py del_amnezia " .. luci.util.shellquote(tag) .. " >/dev/null 2>&1 &")
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_select()
    local tag = luci.http.formvalue("tag")
    if tag then
        os.execute("/usr/bin/shuka_manager.py select " .. luci.util.shellquote(tag) .. " >/dev/null 2>&1 &")
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_force_ping()
    os.execute("rm -f /tmp/ping_* 2>/dev/null")
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_start()
    os.execute("/usr/bin/shuka_manager.py start >/dev/null 2>&1 &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end

function action_stop()
    os.execute("/usr/bin/shuka_manager.py stop >/dev/null 2>&1 &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end

function action_data()
    local util = require "luci.util"
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    local rx = "0"
    local tx = "0"
    local interface_up = false
    
    local tun_rx = util.exec("cat /sys/class/net/tun-shuka/statistics/rx_bytes 2>/dev/null")
    local tun_tx = util.exec("cat /sys/class/net/tun-shuka/statistics/tx_bytes 2>/dev/null")
    local awg_rx = util.exec("cat /sys/class/net/awg0/statistics/rx_bytes 2>/dev/null")
    local awg_tx = util.exec("cat /sys/class/net/awg0/statistics/tx_bytes 2>/dev/null")
    
    if tun_rx ~= "" and tun_rx ~= "0" then
        rx, tx = tun_rx, tun_tx
        interface_up = (util.exec("ip addr show tun-shuka 2>/dev/null | grep 'inet '") ~= "")
    elseif awg_rx ~= "" then
        rx, tx = awg_rx, awg_tx
        interface_up = (util.exec("ip addr show awg0 2>/dev/null | grep 'inet '") ~= "")
    end
    
    local ip = util.exec("curl -s --connect-timeout 2 ifconfig.me")
    if ip == "" then ip = "Offline" end
    
    local servers = {}
    local active_tag = ""
    
    local config_raw = util.exec("cat /etc/sing-box/config.json 2>/dev/null")
    if config_raw ~= "" then
        local config = json.parse(config_raw)
        if config and config.outbounds then
            for _, ob in ipairs(config.outbounds) do
                if ob.type == "vless" or ob.type == "shadowsocks" or ob.type == "wireguard" or ob.type == "trojan" then
                    table.insert(servers, {tag = ob.tag, type = ob.type, server = ob.server})
                end
            end
        end
    end
    
    local am_files = util.exec("ls /etc/amneziawg/profiles/ 2>/dev/null")
    if am_files ~= "" then
        for f in am_files:gmatch("[^\r\n]+") do
            if f:match("%.conf$") then
                local tag = f:gsub("%.conf$", "")
                table.insert(servers, {tag = tag, type = "amneziawg", server = "VPN"})
            end
        end
    end

    local state = json.parse(util.exec("cat /etc/sing-box/state.json 2>/dev/null") or "{}")
    if state and state.active_tag then active_tag = state.active_tag end
    
    local is_running = (util.exec("pgrep sing-box") ~= "") or (util.exec("ip link show awg0 2>/dev/null") ~= "")
    
    local pings = {}
    for _, s in ipairs(servers) do
        if s.server and s.server ~= "VPN" then
            local res = util.exec("ping -c 1 -W 1 " .. s.server .. " 2>/dev/null | grep -o 'time=[0-9.]*' | cut -d= -f2")
            local p = tonumber(res)
            pings[s.tag] = p and math.floor(p + 0.5) or -1
        else
            pings[s.tag] = -1
        end
    end

    http.prepare_content("application/json")
    http.write_json({
        rx = strip(rx), tx = strip(tx), ip = strip(ip),
        servers = servers, pings = pings, active_tag = active_tag,
        is_running = is_running, interface_up = interface_up
    })
end

function action_gui()
    local fs = require "nixio.fs"
    local util = require "luci.util"
    local sub_url = fs.access("/etc/sing-box/sub_url.txt") and util.exec("cat /etc/sing-box/sub_url.txt") or ""

    luci.http.prepare_content("text/html")
    luci.http.write([[
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Shuka Hybrid</title>
    <style>
        :root { --bg: #0f172a; --card: #1e293b; --accent: #38bdf8; --text: #f1f5f9; --dim: #94a3b8; --success: #22c55e; --danger: #ef4444; --warn: #f59e0b; }
        body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); margin: 0; padding: 15px; }
        .container { max-width: 1000px; margin: 0 auto; display: grid; grid-template-columns: 1fr 320px; gap: 20px; }
        @media (max-width: 800px) { .container { grid-template-columns: 1fr; } }
        .card { background: var(--card); padding: 20px; border-radius: 12px; border: 1px solid #334155; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; margin-bottom: 20px; }
        .stat-box { background: rgba(0,0,0,0.2); padding: 12px; border-radius: 8px; text-align: center; border: 1px solid #334155; }
        .stat-v { font-size: 16px; font-weight: bold; color: var(--accent); display: block; }
        .stat-l { font-size: 10px; color: var(--dim); text-transform: uppercase; }
        .btn { padding: 10px 15px; border-radius: 6px; border: none; cursor: pointer; font-weight: bold; font-size: 13px; transition: 0.2s; text-decoration: none; display: inline-block; }
        .btn-primary { background: var(--accent); color: #000; }
        .btn-stop { background: var(--danger); color: #fff; }
        .btn-wide { width: 100%; margin-top: 10px; }
        .server-list { height: 500px; overflow-y: auto; background: rgba(0,0,0,0.2); border-radius: 8px; padding: 5px; }
        .server-item { background: rgba(255,255,255,0.05); padding: 10px; border-radius: 6px; margin-bottom: 5px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; border: 1px solid transparent; }
        .server-item:hover { border-color: var(--accent); background: rgba(255,255,255,0.1); }
        .server-item.active { border-color: var(--accent); background: rgba(56,189,248,0.15); }
        .dot { width: 8px; height: 8px; background: var(--success); border-radius: 50%; display: inline-block; margin-right: 8px; box-shadow: 0 0 8px var(--success); }
        input { width: 100%; background: #000; color: #fff; border: 1px solid #334155; padding: 10px; border-radius: 6px; box-sizing: border-box; }
        pre { background: #000; color: #10b981; padding: 10px; border-radius: 6px; font-size: 11px; height: 200px; overflow: auto; border: 1px solid #333; }
        .section-t { font-size: 15px; color: var(--accent); margin-bottom: 10px; border-left: 3px solid var(--accent); padding-left: 10px; }
    </style>
    <div class="container">
        <div class="left-col">
            <div class="card">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
                    <h2 style="margin:0">🚀 Shuka Hybrid</h2>
                    <div>
                        <a href="]] .. luci.dispatcher.build_url("admin", "services", "shuka", "start") .. [[" class="btn btn-primary">СТАРТ</a>
                        <a href="]] .. luci.dispatcher.build_url("admin", "services", "shuka", "stop") .. [[" class="btn btn-stop">СТОП</a>
                    </div>
                </div>
                <div class="stats">
                    <div class="stat-box"><span id="rx-val" class="stat-v">0.00 MB</span><span class="stat-l">ВХОД</span></div>
                    <div class="stat-box"><span id="tx-val" class="stat-v">0.00 MB</span><span class="stat-l">ИСХОД</span></div>
                    <div class="stat-box"><span id="ip-badge" class="stat-v">---</span><span class="stat-l">IP</span></div>
                    <div class="stat-box"><span id="status-label" class="stat-v">---</span><span class="stat-l">СТАТУС</span></div>
                </div>
                <div class="stat-box" style="margin-bottom:20px;"><span id="active-server-label" class="stat-v">---</span><span class="stat-l">АКТИВНЫЙ СЕРВЕР</span></div>

                <div class="section-t">🔗 ПОДПИСКА</div>
                <div style="display:flex; gap:10px; margin-bottom:10px;">
                    <input type="text" id="sub-url" value="]] .. sub_url .. [[">
                    <button class="btn btn-primary" onclick="sync(this)">ОБНОВИТЬ</button>
                    <button class="btn btn-stop" onclick="clearSub(this)">УДАЛИТЬ</button>
                </div>

                <div class="section-t" style="margin-top:20px;">✨ AMNEZIAWG ИМПОРТ</div>
                <form method="post" action="]] .. luci.dispatcher.build_url("admin", "services", "shuka", "amnezia_upload") .. [[" enctype="multipart/form-data">
                    <input type="file" name="amneziadata" id="amneziadata" style="display:none;" onchange="this.form.submit()">
                    <button type="button" class="btn btn-primary btn-wide" style="background:#6f42c1;color:#fff" onclick="document.getElementById('amneziadata').click()">ВЫБРАТЬ .CONF ФАЙЛ</button>
                </form>

                <div class="section-t" style="margin-top:20px;">📋 ЖУРНАЛ СОБЫТИЙ</div>
                <pre id="log-output">]] .. util.exec("logread | grep -Ei 'sing-box|amnezia' | tail -n 30") .. [[</pre>
            </div>
        </div>

        <div class="right-col">
            <div class="card">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
                    <h3 class="section-t" style="margin:0">🌍 СЕРВЕРЫ</h3>
                    <button class="btn btn-primary" style="padding:4px 8px; font-size:10px;" onclick="forcePing(this)">PING</button>
                </div>
                <div id="server-list" class="server-list">Загрузка...</div>
            </div>
        </div>
    </div>

    <script>
        function formatBytes(b) {
            b = parseInt(b) || 0;
            if (b === 0) return "0.00 MB";
            let v = b / 1024 / 1024;
            return v > 1024 ? (v/1024).toFixed(2) + " GB" : v.toFixed(2) + " MB";
        }

        function updateData() {
            fetch(']] .. luci.dispatcher.build_url("admin", "services", "shuka", "data") .. [[')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('rx-val').innerText = formatBytes(data.rx);
                    document.getElementById('tx-val').innerText = formatBytes(data.tx);
                    document.getElementById('ip-badge').innerText = data.ip;
                    document.getElementById('active-server-label').innerText = data.active_tag || "---";
                    
                    const sl = document.getElementById('status-label');
                    if (data.interface_up) { sl.innerText = 'В СЕТИ'; sl.style.color = 'var(--success)'; }
                    else if (data.is_running) { sl.innerText = 'ЗАПУСК...'; sl.style.color = 'var(--warn)'; }
                    else { sl.innerText = 'ВЫКЛЮЧЕН'; sl.style.color = 'var(--danger)'; }

                    const list = document.getElementById('server-list');
                    list.innerHTML = '';
                    if (data.servers) {
                        data.servers.forEach(s => {
                            const active = s.tag === data.active_tag;
                            const div = document.createElement('div');
                            div.className = 'server-item' + (active ? ' active' : '');
                            div.onclick = () => selectServer(s.tag);
                            
                            let pV = data.pings[s.tag];
                            let pB = '';
                            if (pV !== undefined && pV !== -1) {
                                let c = pV < 100 ? 'var(--success)' : (pV < 250 ? 'var(--warn)' : 'var(--danger)');
                                pB = '<span style="background:'+c+'; color:#000; padding:2px 4px; border-radius:4px; font-size:10px; font-weight:bold; margin-left:8px;">'+pV+'ms</span>';
                            }

                            div.innerHTML = '<div>' + (active ? '<span class="dot"></span>' : '') + '<b>'+s.tag+'</b>'+pB+'</div>' + 
                                            '<div style=\"display:flex; align-items:center; gap:5px;\"><small style=\"color:var(--dim)\">'+s.type+'</small>' + 
                                            (s.type === 'amneziawg' ? '<span onclick=\"event.stopPropagation(); deleteAmnezia(\''+s.tag+'\')\" style=\"color:var(--danger); cursor:pointer;\">✕</span>' : '') + '</div>';
                            list.appendChild(div);
                        });
                    }
                });
        }

        function sync(btn) {
            const url = document.getElementById('sub-url').value;
            if (!url) return;
            btn.innerText = '⏳...'; btn.disabled = true;
            fetch(']] .. luci.dispatcher.build_url("admin", "services", "shuka", "sync") .. [[?url=' + encodeURIComponent(url)).then(() => {
                setTimeout(() => { btn.innerText = 'ОБНОВИТЬ'; btn.disabled = false; updateData(); }, 3000);
            });
        }

        function clearSub(btn) {
            if (!confirm('Очистить всё?')) return;
            btn.innerText = '⏳...'; btn.disabled = true;
            fetch(']] .. luci.dispatcher.build_url("admin", "services", "shuka", "clear_sub") .. [[').then(() => {
                setTimeout(() => { btn.innerText = 'УДАЛИТЬ'; btn.disabled = false; updateData(); }, 2000);
            });
        }

        function selectServer(tag) {
            fetch(']] .. luci.dispatcher.build_url("admin", "services", "shuka", "select") .. [[?tag=' + encodeURIComponent(tag)).then(() => setTimeout(updateData, 1000));
        }

        function deleteAmnezia(tag) {
            if (confirm('Удалить ' + tag + '?')) {
                fetch(']] .. luci.dispatcher.build_url("admin", "services", "shuka", "delete_amnezia") .. [[?tag=' + encodeURIComponent(tag)).then(() => setTimeout(updateData, 1000));
            }
        }

        function forcePing(btn) {
            btn.innerText = '...';
            fetch(']] .. luci.dispatcher.build_url("admin", "services", "shuka", "force_ping") .. [[').then(() => setTimeout(() => { btn.innerText = 'PING'; updateData(); }, 1000));
        }

        setInterval(updateData, 5000);
        updateData();
    </script>
</body>
</html>
]])
end
