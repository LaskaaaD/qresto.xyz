# QResto - Checklista Obrony DevOps

## 1. Wymagania Obowiazkowe (Status)

- [x] Publiczne repozytorium z aplikacja
- [x] IaC: provisioning serwera przez Ansible
- [x] CI/CD: build + publikacja artefaktu po pushu
- [x] CD: automatyczny deploy po pushu na `main`
- [x] Monitoring infrastruktury i aplikacji
- [x] Powiadomienia o statusie pipeline i deployu
- [x] Minimalna dokumentacja uruchomienia i wdrozenia

## 2. Gdzie to jest w repo

- IaC:
  - `ansible/setup.yml`
  - `scripts/provision.sh`
- CI/CD:
  - `.github/workflows/ci-cd.yml`
- Kontenery i siec:
  - `docker-compose.yml`
  - `Dockerfile`
- Monitoring:
  - `scripts/bootstrap-zabbix.sh`
  - `scripts/push-cert-metric.sh`
  - `scripts/check-acme-renew.sh`
- Backup:
  - `scripts/backup.sh`

## 3. Co pokazac na demo (10-12 min)

1. Push do galezi roboczej -> test + build + push do GHCR + Telegram.
2. Push/Merge do `main` -> automatyczny deploy na VPS + Telegram.
3. `docker compose ps` na VPS (status uslug).
4. `curl https://<domena>/health` (status aplikacji).
5. Wejscie do Zabbix i podglad hosta/web scenarios/triggerow.
6. `bash scripts/traffic-mode.sh high` i pokaz wielu replik app.

## 4. Twarde argumenty na pytania komisji

- Dlaczego IaC jest idempotentne:
  - Ansible zadania deklaratywne (`state: present`, `lineinfile`, `cron`, `ufw`).
- Jak minimalizujemy ekspozycje:
  - publicznie tylko 80/443 przez Traefik;
  - Mongo bez mapowania portu;
  - Zabbix server mapowany tylko na localhost hosta (`127.0.0.1:10051`).
- Jak dbamy o operacje:
  - backup plikow + dump Mongo (`scripts/backup.sh`);
  - healthcheck cron + endpointy `/live`, `/ready`, `/health`.
- Jak wyglada artefakt:
  - obraz Docker publikowany do GHCR.

## 5. Ograniczenia (uczciwie, ale kontrolowanie)

- Warstwa aplikacji jest MVP i nie udaje pelnego produktu komercyjnego.
- Zakres pracy celowo skupiony na DevOps, automatyzacji i monitoringu.
- Testy aplikacji sa podstawowe; kluczowe procesy operacyjne i wdrozeniowe sa zautomatyzowane.
