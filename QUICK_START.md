# QResto — Szybki Start 

Instrukcja krok po kroku: od zera do działającej aplikacji na produkcji.

> **Wymagania wstępne:**
> - VPS z Ubuntu 22.04+ i dostępem SSH (root)
> - Domena podpięta do Cloudflare
> - Zainstalowany Git
> - Konto na GitHub
> - Terminal WSL / Linux / macOS

## Wymagane sekrety repozytorium (GitHub Actions)

Przed pierwszym deployem dodaj w GitHub (Settings -> Secrets and variables -> Actions):

- `CF_DNS_API_TOKEN` - jak uzyskać: [sekcja 1](#1-konfiguracja-dns-w-cloudflare)
- `TELEGRAM_BOT_TOKEN` - jak uzyskać: [sekcja 2](#2-utworzenie-bota-telegram-powiadomienia)
- `TELEGRAM_CHAT_ID` - jak uzyskać: [sekcja 2](#2-utworzenie-bota-telegram-powiadomienia)
- `VPS_HOST` - wartość: IP VPS z [sekcji 5](#5-provisioning-serwera)
- `VPS_SSH_USER` - wartość: użytkownik deploy z [sekcji 5](#5-provisioning-serwera)
- `VPS_SSH_KEY` - jak uzyskać: [sekcja 4](#4-klonowanie-repozytorium-i-przygotowanie-ssh)
- `VPS_SSH_PORT` (opcjonalnie) - wartość: port SSH z [sekcji 5](#5-provisioning-serwera)

---

## 1. Konfiguracja DNS w Cloudflare

1. Zaloguj się do [Cloudflare](https://dash.cloudflare.com) i wybierz swoją domenę.
2. Przejdź do zakładki **DNS → Records** i dodaj dwa rekordy:

   | Typ | Nazwa | Wartość | Proxy |
   | --- | --- | --- | --- |
   | A | `@` | IP Twojego VPS | zgodnie z Twoją konfiguracją Cloudflare |
   | A | `*` | IP Twojego VPS | zgodnie z Twoją konfiguracją Cloudflare |

3. Utwórz token API do edycji DNS:
   - Przejdź do **My Profile → API Tokens → Create Token**
   - Wybierz szablon **Edit zone DNS** lub utwórz własny z uprawnieniami: **Zone → DNS → Edit**
   - Ogranicz token do swojej domeny (Zone Resources → Include → Specific zone)
   - Skopiuj wygenerowany token — będzie potrzebny w dwóch miejscach (GitHub Secrets i plik `.env`)

---

## 2. Utworzenie bota Telegram (powiadomienia)

Bot Telegram wysyła powiadomienia o statusie buildów, deployów i alertów monitoringu.

1. Otwórz Telegram i napisz do [@BotFather](https://t.me/BotFather): `/newbot`
2. Podaj nazwę i username bota — otrzymasz **token bota** (np. `123456:ABC-DEF...`)
3. Utwórz grupę lub kanał, dodaj do niej bota
4. Aby uzyskać **Chat ID**:
   - Napisz wiadomość na grupie/kanale
   - Otwórz w przeglądarce: `https://api.telegram.org/bot<TWÓJ_TOKEN>/getUpdates`
   - Znajdź pole `"chat":{"id": ...}` — to jest Twój Chat ID

---

## 3. Utworzenie repozytorium na GitHub

1. Utwórz nowe repozytorium na GitHub (np. `qrestoxyz`).
2. Dodaj wymagane sekrety zgodnie z sekcją na początku tego pliku.
3. *(Opcjonalnie)* Włącz branch protection dla `main`:
   - **Settings → Branches → Add rule** → Branch name: `main`
   - Zaznacz *Require a pull request before merging* i *Require status checks to pass*

---

## 4. Klonowanie repozytorium i przygotowanie SSH

W terminalu WSL / Linux:

```bash
# Sklonuj repozytorium
git clone git@github.com:TwojUser/TwojeRepo.git
cd TwojeRepo

# Zainstaluj Ansible (jeśli nie masz)
sudo apt update && sudo apt install -y ansible
```

Następnie utwórz klucz SSH (jeśli jeszcze go nie masz):

```bash
ssh-keygen -t ed25519 -C "qresto-deploy"
# Domyślna ścieżka: ~/.ssh/id_ed25519
```

Skopiuj klucz publiczny na VPS:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@vps_ip_v4
```

Sprawdź, czy możesz połączyć się z VPS:

```bash
ssh -p PORT_SSH user@vps_ip_v4
```

---

## 5. Provisioning serwera

Skrypt `provision.sh` interaktywnie zbiera dane i uruchamia Ansible, który:
- aktualizuje system i instaluje pakiety bazowe
- konfiguruje firewall (UFW), fail2ban, SWAP (2 GB)
- instaluje Docker Engine + Docker Compose plugin
- tworzy użytkownika deploy z kluczem SSH i sudo bez hasła
- przygotowuje katalog `/opt/qresto` z szablonem `.env.bootstrap`
- konfiguruje crony: health-check, backup, metryki certyfikatów, auto-bootstrap Zabbix
- wyłącza logowanie root i hasłowe przez SSH

Uruchom w katalogu projektu:

```bash
bash scripts/provision.sh
```

Skrypt zapyta o:
- **IP VPS** — adres serwera
- **Użytkownik SSH** — domyślnie `root` (do pierwszego provisioningu)
- **Port SSH do pierwszego połączenia** — domyślnie `22`
- **Docelowy port SSH po hardeningu** — domyślnie taki sam jak port początkowy
- **Ścieżka do klucza prywatnego SSH** — domyślnie `~/.ssh/id_ed25519`
- **Ścieżka do klucza publicznego SSH** — kopiowany na VPS dla użytkownika deploy
- **Nazwa użytkownika deploy** — domyślnie `qresto_user` (zapamiętaj — wpisz tę samą wartość jako GitHub Secret `VPS_SSH_USER`)
- **Domena główna** — np. `qresto.xyz`
- **Domeny aplikacji, WWW i Zabbix** — domyślnie wypełnione na podstawie domeny głównej
- **E-mail SSL** — dla certyfikatów Let's Encrypt

Po zakończeniu skrypt:
- przygotuje na VPS szablon `/opt/qresto/.env.bootstrap` (z podmienionymi domenami i e-mailem SSL z promptów)
- wyświetli podsumowanie z dalszymi krokami

Po provisioningu zaloguj się ponownie (już użytkownikiem deploy, zwykle na nowym porcie SSH):

```bash
ssh -p PORT_SSH qresto_user@IP_TWOJEGO_VPS
```

---

## 6. Konfiguracja pliku `.env` na VPS

Będąc zalogowanym na VPS jako użytkownik deploy, utwórz plik `.env` na podstawie szablonu bootstrap:

```bash
cp /opt/qresto/.env.bootstrap /opt/qresto/.env
nano /opt/qresto/.env
```

Uzupełnij wszystkie wartości `CHANGE_ME`:

```ini
# -------- Routing i SSL (Traefik) --------
# Te pola są już uzupełnione jeśli użyłeś provision.sh
ROOT_DOMAIN=qresto.xyz
APP_DOMAIN=qresto.xyz
APP_WWW_DOMAIN=www.qresto.xyz
ZABBIX_DOMAIN=zabbix.qresto.xyz
SSL_EMAIL=admin@qresto.xyz

# -------- Cloudflare --------
CF_DNS_API_TOKEN=wklej_token_z_cloudflare

# -------- Obraz aplikacji (uzupełni się automatycznie przy pierwszym deployu) --------
APP_IMAGE=ghcr.io/twojuser/twojerepo:main

# -------- MongoDB --------
MONGO_USER=qresto_admin
MONGO_PASS=wpisz_silne_haslo_mongodb
MONGO_DB=qresto
MONGODB_URI=mongodb://qresto_admin:wpisz_silne_haslo_mongodb@mongodb:27017/qresto?authSource=admin

# -------- Sesje Express --------
SESSION_SECRET=wpisz_losowy_ciag_znakow

# -------- Zabbix --------
ZABBIX_DB_USER=zabbix
ZABBIX_DB_PASS=wpisz_silne_haslo_zabbix
ZABBIX_API_USER=Admin
ZABBIX_API_PASSWORD=zabbix
ZABBIX_HOSTNAME=qresto-vps-agent

# -------- Telegram --------
TELEGRAM_BOT_TOKEN=wklej_token_bota
TELEGRAM_CHAT_ID=wklej_chat_id
TELEGRAM_CERT_ALERT_DAYS=20
```

> **Podpowiedź:** Silne hasło możesz wygenerować poleceniem:
> ```bash
> openssl rand -base64 32
> ```

> **Ważne:** jeśli zmieniasz `MONGO_USER`, `MONGO_PASS` lub `MONGO_DB`, zaktualizuj też `MONGODB_URI`, żeby dane logowania były spójne.

> **Kolejność krytyczna:** najpierw provisioning (`provision.sh`), potem uzupełnienie `/opt/qresto/.env` i sekretów GitHub, a dopiero na końcu pierwszy `git push origin main`.

---

## 7. Pierwszy deploy

Wypchnij kod na `main`:

```bash
git add .
git commit -m "Initial deploy"
git push origin main
```

Przed pushem upewnij się, że:

1. Na VPS istnieje `/opt/qresto/.env` i nie ma już wartości `CHANGE_ME`.
2. W GitHub Secrets dodane są wymagane sekrety (`CF_DNS_API_TOKEN`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `VPS_HOST`, `VPS_SSH_USER`, `VPS_SSH_KEY`, opcjonalnie `VPS_SSH_PORT`).

Podgląd pipeline:

1. Wejdź w GitHub -> `Actions`.
2. Otwórz najnowszy workflow `CI/CD Pipeline`.
3. Sprawdź kolejno statusy: `test` -> `build-and-push` -> `deploy`.

Pipeline GitHub Actions automatycznie:
1. Uruchomi testy (`npm test`)
2. Zbuduje obraz Docker i opublikuje go do GHCR
3. Wdroży aplikację na VPS (`docker compose up -d`)
4. Wyśle powiadomienie na Telegram

Po 1–2 minutach aplikacja powinna być dostępna pod Twoją domeną (`https://qresto.xyz`).

---

## 8. Weryfikacja

Na VPS sprawdź, czy wszystkie kontenery działają:

```bash
cd /opt/qresto
sudo docker compose ps
```

Powinieneś zobaczyć uruchomione usługi: `traefik`, `qresto_app`, `qresto_mongo`, `zabbix-*`.

Sprawdź health-check aplikacji:

```bash
curl -s https://twoja-domena.xyz/health | jq .
```

Dodatkowe szybkie testy:

```bash
curl -s https://twoja-domena.xyz/live | jq .
curl -s https://twoja-domena.xyz/ready | jq .
```

Jeśli coś nie działa, sprawdź logi:

```bash
cd /opt/qresto
sudo docker compose logs --tail=100 app
sudo docker compose logs --tail=100 traefik
```

Oczekiwana odpowiedź:
```json
{
  "status": "ok",
  "database": { "status": "connected" }
}
```

Panel Zabbix dostępny pod: `https://zabbix.twoja-domena.xyz`
(domyślne dane: `Admin` / `zabbix` — zmień hasło po pierwszym logowaniu!)

---

## Rozwiązywanie problemów

| Problem | Rozwiązanie |
| --- | --- |
| Certyfikat SSL nie działa | Sprawdź rekordy DNS/proxy w Cloudflare i logi Traefika: `sudo docker logs traefik` |
| Aplikacja nie odpowiada | `sudo docker compose logs app` — sprawdź, czy MongoDB jest dostępne |
| Deploy nie działa | Sprawdź sekrety GitHub (zwłaszcza `VPS_SSH_KEY` — musi zawierać pełny klucz prywatny) |
| Nie można połączyć się SSH po provisioningu | Upewnij się, że używasz poprawnego `PORT_SSH` i użytkownika `qresto_user`; sprawdź też reguły UFW |
| Zabbix nie uruchamia się | Zabbix potrzebuje ~2 min na pierwszą inicjalizację bazy. Sprawdź: `sudo docker compose logs zabbix-server` |
| Bot Telegram nie wysyła | Sprawdź, czy bot jest dodany do grupy/kanału i czy `CHAT_ID` jest poprawny |
