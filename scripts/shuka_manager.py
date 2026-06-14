#!/usr/bin/env python3
import json, os, sys, urllib.request, urllib.parse, base64, re, time

CONFIG_PATH = "/etc/sing-box/config.json"
TEMPLATE_PATH = "/etc/sing-box/config.json.template"
SUB_URL_FILE = "/etc/sing-box/sub_url.txt"
AMNEZIA_PROFILES = "/etc/amneziawg/profiles/"
STATE_FILE = "/etc/sing-box/state.json"
CONN_FLAG = "/tmp/shuka_connecting"
SYNC_FLAG = "/tmp/shuka_syncing"

def load_json(path):
    if os.path.exists(path):
        try:
            with open(path, 'r') as f: return json.load(f)
        except: pass
    return {}

def save_json(path, data):
    with open(path, 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)

def set_state(tag, engine):
    save_json(STATE_FILE, {"active_tag": tag, "engine": engine})

def stop_all():
    os.system("killall sing-box 2>/dev/null")
    os.system("ip link delete awg0 2>/dev/null")
    os.system("/usr/bin/amneziawg-stop.sh 2>/dev/null")
    os.system("ip route flush cache")

def parse_link(link):
    try:
        link = link.strip()
        if not link.startswith("vless://"): return None
        m = re.match(r"vless://([^@]+)@([^:]+):(\d+)\?([^#]+)(#.+)?", link)
        if m:
            u, h, p, pa, t = m.groups()
            tag = urllib.parse.unquote(t[1:]) if t else "VLESS"
            pars = dict(urllib.parse.parse_qsl(pa))
            out = {"type":"vless","tag":tag,"server":h,"server_port":int(p),"uuid":u,"tls":{"enabled":True,"server_name":pars.get("sni",""),"utls":{"enabled":True,"fingerprint":"chrome"}}}
            if pars.get("security") == "reality": out["tls"]["reality"] = {"enabled":True,"public_key":pars.get("pbk",""),"short_id":pars.get("sid","")}
            if pars.get("flow"): out["flow"] = pars.get("flow")
            return out
    except: pass
    return None

def apply_fw(iface):
    os.system(f"iptables -I FORWARD -i br-lan -o {iface} -j ACCEPT 2>/dev/null")
    os.system(f"iptables -I FORWARD -i {iface} -o br-lan -j ACCEPT 2>/dev/null")
    os.system(f"iptables -t nat -I POSTROUTING -o {iface} -j MASQUERADE 2>/dev/null")

def select_server(tag):
    if not tag: return
    os.system("touch " + CONN_FLAG)
    tag_clean = tag.replace(".conf", "")
    conf_path = AMNEZIA_PROFILES + tag_clean + ".conf"
    
    if os.path.exists(conf_path):
        stop_all()
        os.system("ip link add dev awg0 type amneziawg")
        os.system("cp '" + conf_path + "' /etc/amneziawg/awg0.conf")
        os.system("/usr/bin/start_shuka.sh &")
        set_state(tag_clean, "amneziawg")
    else:
        c = load_json(CONFIG_PATH)
        if "route" in c and "rules" in c["route"]:
            for r in c["route"]["rules"]:
                if r.get("action") == "hijack-dns": continue
                if r.get("outbound") not in ["direct","dns-out","block","any"]: r["outbound"] = tag
        if "dns" in c and "servers" in c["dns"]:
            for s in c["dns"]["servers"]:
                # Исправляем detour, чтобы он указывал на тег сервера, а не на слово proxy
                if s.get("tag") == "dns-proxy": s["detour"] = tag
        save_json(CONFIG_PATH, c)
        stop_all()
        cmd = "export ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true; export ENABLE_DEPRECATED_OUTBOUND_DNS_RULE_ITEM=true; export ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true; /usr/bin/sing-box run -c /etc/sing-box/config.json &"
        os.system(cmd)
        apply_fw("tun-shuka")
        set_state(tag, "sing-box")
    os.system("(sleep 15 && rm -f " + CONN_FLAG + ") &")

def main():
    if len(sys.argv) < 2: return
    cmd = sys.argv[1]
    if cmd == "sync":
        os.system("touch " + SYNC_FLAG)
        try:
            if not os.path.exists(SUB_URL_FILE): return
            with open(SUB_URL_FILE) as f: url = f.read().strip()
            req = urllib.request.Request(url, headers={'User-Agent': 'v2rayNG/1.8.5'})
            with urllib.request.urlopen(req, timeout=15) as r:
                data = r.read().decode('utf-8', errors='ignore').strip()
                if not data.startswith('vless://'):
                    data = base64.b64decode(data + '='*(-len(data)%4)).decode('utf-8', errors='ignore')
                links = data.splitlines()
                obs = []
                for l in links:
                    p = parse_link(l)
                    if p: obs.append(p)
                if obs:
                    cfg = load_json(TEMPLATE_PATH)
                    cfg["outbounds"] = obs + [o for o in cfg.get("outbounds",[]) if o["type"] not in ["vless"]]
                    save_json(CONFIG_PATH, cfg)
        finally:
            time.sleep(1)
            os.system("rm -f " + SYNC_FLAG)
    elif cmd == "select": select_server(sys.argv[2])
    elif cmd == "stop": stop_all(); set_state("", "none"); os.system("rm -f " + CONN_FLAG)
    elif cmd == "start":
        state = load_json(STATE_FILE)
        if state.get("active_tag"): select_server(state["active_tag"])
    elif cmd == "amnezia":
        path = sys.argv[2]
        if os.path.exists(path):
            name = "Imported-" + base64.b32encode(os.urandom(2)).decode().strip("=")
            if not os.path.exists(AMNEZIA_PROFILES): os.makedirs(AMNEZIA_PROFILES)
            os.system(f"cp '{path}' '{AMNEZIA_PROFILES}{name}.conf'")
    elif cmd == "del_amnezia":
        tag = sys.argv[2]
        path = AMNEZIA_PROFILES + tag + ".conf"
        if os.path.exists(path):
            os.remove(path)
            st = load_json(STATE_FILE)
            if st.get("active_tag") == tag: stop_all(); set_state("", "none")
    elif cmd == "clear_sub":
        if os.path.exists(SUB_URL_FILE): os.remove(SUB_URL_FILE)
        cfg = load_json(TEMPLATE_PATH)
        save_json(CONFIG_PATH, cfg)
        stop_all(); set_state("", "none")

if __name__ == "__main__": main()
