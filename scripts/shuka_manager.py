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
            return out
    except: pass
    return None

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
            time.sleep(15)
            os.system("rm -f " + SYNC_FLAG)
            
    elif cmd == "select":
        tag = sys.argv[2]
        os.system("touch " + CONN_FLAG)
        if os.path.exists(AMNEZIA_PROFILES + tag + ".conf"):
            stop_all()
            os.system("ip link add dev awg0 type amneziawg")
            os.system("cp '" + AMNEZIA_PROFILES + tag + ".conf' /etc/amneziawg/awg0.conf")
            os.system("/usr/bin/start_shuka.sh &")
            save_json(STATE_FILE, {"active_tag": tag, "engine": "amneziawg"})
        else:
            c = load_json(CONFIG_PATH)
            if "route" in c and "rules" in c["route"]:
                for r in c["route"]["rules"]:
                    if "outbound" in r and r["outbound"] not in ["direct","block","dns-out","any"]: r["outbound"] = tag
            save_json(CONFIG_PATH, c)
            stop_all()
            os.system("export ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true; /usr/bin/sing-box run -c /etc/sing-box/config.json &")
            save_json(STATE_FILE, {"active_tag": tag, "engine": "sing-box"})
        os.system("(sleep 15 && rm -f " + CONN_FLAG + ") &")

    elif cmd == "stop":
        stop_all()
        save_json(STATE_FILE, {"active_tag": "", "engine": "none"})
        
    elif cmd == "start":
        st = load_json(STATE_FILE)
        if st.get("active_tag"):
            # Вызываем саму программу с командой select
            os.system(f"/usr/bin/python3 /usr/bin/shuka_manager.py select '{st['active_tag']}'")
            
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
            if st.get("active_tag") == tag:
                stop_all()
                save_json(STATE_FILE, {"active_tag": "", "engine": "none"})
                
    elif cmd == "clear_sub":
        if os.path.exists(SUB_URL_FILE): os.remove(SUB_URL_FILE)
        cfg = load_json(TEMPLATE_PATH)
        save_json(CONFIG_PATH, cfg)
        stop_all()
        save_json(STATE_FILE, {"active_tag": "", "engine": "none"})

if __name__ == "__main__": main()
