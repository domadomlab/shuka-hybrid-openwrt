#!/usr/bin/env python3
import os, time, sys, json, re

PORTS = ['/dev/ttyACM0', '/dev/ttyACM2', '/dev/ttyACM1']

def send_at(cmd, timeout=3):
    last_error = ""
    for port in PORTS:
        if not os.path.exists(port): continue
        try:
            fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
            time.sleep(0.1)
            try:
                while os.read(fd, 4096): pass
            except: pass
            os.write(fd, (cmd + '\r\n').encode())
            res = ''
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    chunk = os.read(fd, 4096).decode(errors='ignore')
                    if chunk:
                        res += chunk
                        if 'OK' in res or 'ERROR' in res: break
                except BlockingIOError:
                    time.sleep(0.1)
            os.close(fd)
            lines = [l.strip() for l in res.split('\n') if l.strip() and l.strip() != cmd]
            return "\n".join(lines)
        except Exception as e:
            last_error = str(e)
            continue
    return f"ERROR: {last_error}"

def get_aggregation():
    xlec = send_at('AT+XLEC?')
    gtcainfo = send_at('AT+GTCAINFO?')
    mimo = send_at('at@errc:pcell_scell_mimoLayer_status()')
    usb_speed = send_at('at@usbmwtestfw:usb_get_enum_speed()')
    return json.dumps({
        "active_ca": xlec,
        "ca_details": gtcainfo,
        "mimo_status": mimo,
        "usb_speed": usb_speed
    }, ensure_ascii=False, indent=2)

def get_status():
    csq = send_at('AT+CSQ')
    temp = send_at('AT+MTSM=1')
    ver = send_at('AT+GTPKGVER?')
    sig = "N/A"
    m = re.search(r'\+CSQ:\s*(\d+,\d+)', csq)
    if m: sig = m.group(1)
    
    # Для совместимости с новым интерфейсом отдаем пустые поля
    return json.dumps({
        "csq": sig,
        "signal": sig,
        "temperature": temp,
        "firmware": ver,
        "raw_csq": csq,
        "primary_band": "N/A",
        "scells": [],
        "ca_active": False,
        "operator": "Unknown"
    }, ensure_ascii=False)

if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit(1)
    action = sys.argv[1]
    if action == "status":
        print(get_status())
    elif action == "aggregation":
        print(get_aggregation())
    elif action == "reboot":
        print(send_at('AT+CFUN=15'))
    elif action == "set_band":
        print(send_at(f'at+xact=2,,,{sys.argv[2]}'))
    elif action == "restore_ca":
        print(send_at('at@sic:ca_restore(0)'))
    elif action == "cmd":
        print(send_at(sys.argv[2]))
