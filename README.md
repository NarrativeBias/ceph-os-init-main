# ceph-os-init

Ansible-плейбуки для подготовки серверов Ubuntu 24.04 по нашим стандартам и практикам c возможностью дальнейшего деплоя Ceph на них.

## Использование

Запускать из корня репозитория. Инвентарь — один файл; рядом с ним лежат `group_vars/` и `etc-hosts`.

```bash
# 0) Разовая подготовка (на каждый инвентарь)
cp group_vars/all.yml.sample <inventory_dir>/group_vars/all.yml   # заполнить
cp etc-hosts.example <inventory_dir>/etc-hosts                   # заполнить
# В этом репозитории: secrets/vault.yml
# CA: roles/ca-certs/files/{test,dev,prod}/*.crt
# Ceph: roles/ceph-packages/files/*<ceph_repo_ver>*.deb
#   и для нового кластера roles/cluster-init/files/*.tar.gz

# 1) Только подготовка ОС (без Ceph)
ansible-playbook playbooks/01-prepare-srv.yml -i <inventory> -e srv=vse --ask-vault-pass

# 2) Новый кластер Ceph
ansible-playbook playbooks/01-prepare-srv.yml   -i <inventory> -e srv=vse --ask-vault-pass
ansible-playbook playbooks/02-prepare-ceph.yml  -i <inventory> -e srv=vse -e cluster_action=init --ask-vault-pass
# … сборка / bootstrap кластера Ceph …
# … init-плейбук группы UNIX (вне этого репозитория) …
ansible-playbook playbooks/03-post-init.yml     -i <inventory> -e srv=vse --ask-vault-pass
# … чеклист ПНР …
ansible-playbook playbooks/04-finish-pnr.yml    -i <inventory> -e srv=vse --ask-vault-pass

# 3) Расширение кластера (новые хосты в [new])
ansible-playbook playbooks/01-prepare-srv.yml   -i <inventory> -e srv=new --ask-vault-pass
ansible-playbook playbooks/02-prepare-ceph.yml  -i <inventory> -e srv=new -e cluster_action=extend --ask-vault-pass
# … добавление узлов в кластер …
# … init-плейбук группы UNIX (вне этого репозитория) …
ansible-playbook playbooks/03-post-init.yml     -i <inventory> -e srv=new --ask-vault-pass
# … чеклист ПНР …
ansible-playbook playbooks/04-finish-pnr.yml    -i <inventory> -e srv=new --ask-vault-pass

# 4) Уже развёрнутые хосты: только CA + SSSD LDAPS
ansible-playbook playbooks/existing-servers/enable-sssd-tls.yml -i <inventory> -e srv=<group> --ask-vault-pass
```

`--ask-vault-pass` нужен, если расшифровываются `secrets/vault.yml` или vault-зашифрованные сертификаты. Если ничего не vault-зашифровано — можно не указывать.

Опционально: `-e force=yes` обходит остановку preflight, когда на хосте уже есть учётка администратора (*sadm) из плейбука 04.

---

## Назначение

Репозиторий решает две связанные, но разные задачи:

1. **Подготовка хостов** — привести Ubuntu **24.04 (noble)** к принятым у нас стандартам: сеть, репозитории, пакеты, NTP, тюнинг ОС, пользователи и т.п. Для этого достаточно `01-prepare-srv`; Ceph при этом ставить не обязательно.
2. **Развёртывание Ceph** — пользователи и пакеты Ceph, podman/registry, init/extend, образы узлов (`02`). Дальше — внешний init группы UNIX, наш `03-post-init`, чеклист ПНР и финальный `04-finish-pnr`.

| Плейбук | Назначение |
|---|---|
| `01-prepare-srv` | Только ОС: DNS/hostname, `/etc/hosts`, apt-репозитории, пакеты, dnsmasq, NTP, os-tune, RAID CLI, root PV, unix-пользователи. Без `cluster_action`. |
| `02-prepare-ceph` | Ceph-пользователи, локальный `cephadm` .deb, podman, `cluster_action=init\|extend` (registry и ansible на mon при init), pull образов Ceph/node-exporter. |
| `03-post-init` | После init-плейбука группы UNIX: `/etc/hosts`, пользователи/NTP, info по кластеру Ceph, CA (с очисткой старых), SSSD LDAPS, Zabbix, shell prompt. |
| `04-finish-pnr` | Последний шаг подготовки хостов после чеклиста ПНР: продакшен-админы, IPMI, перенос s3-init. |
| `existing-servers/enable-sssd-tls` | CA-доверие и `ad_use_ldaps` на уже развёрнутых хостах (без полного 03). |

Роли в `roles/`; в `ansible.cfg` заданы `roles_path = ./roles` и лог в `~/ansible.log`.

## Инвентарь и группы

Нужен **один файл инвентаря** (при init он копируется на первый mon).

| Группа | Назначение |
|---|---|
| `[vse]` | Все серверы кластера. |
| `[new]` | Добавляемые хосты (обычно новая стойка). При init отсутствует или пуста. Может также входить в `[vse]`. |
| `[mons]`, `[osds]`, … | Ролевые группы. Первый хост в `[mons]` (порядок в инвентаре) — Ansible-контроллер кластера и хост локального registry при init. |

- **Init:** `-e srv=vse -e cluster_action=init` — группа `[new]` должна отсутствовать или быть пустой.
- **Extend:** `-e srv=new -e cluster_action=extend` — плейбук ходит только в `[new]`; уже работающие члены `[vse]` (не из `[new]`) не трогаются.

`roles/cluster-scope` проверяет это на контроллере до подключения к серверам и публикует `cluster_new_hosts`, `cluster_existing_hosts`, `cluster_hosts` для ролей, которым нужен полный список имён.

## Файлы рядом с инвентарём

| Путь | Назначение |
|---|---|
| `group_vars/all.yml` | Из `group_vars/all.yml.sample`: `local_registry`, `ceph_repo_ver`, `seg_fqdn`, `environment_type` и др. |
| `etc-hosts` | Из `etc-hosts.example`: строки `IP FQDN короткое_имя`. Ставится в 01 и снова в 03. |

## Файлы в ролях (общие для инвентарей)

| Путь | Назначение |
|---|---|
| `roles/ca-certs/files/test/*.crt` | Цепочка CA для `test.vtb.ru`. |
| `roles/ca-certs/files/dev/*.crt` | Цепочка CA для `corp.dev.vtb`. |
| `roles/ca-certs/files/prod/*.crt` | Цепочка CA для `cde.vtb`, `inet.vtb`, `cn-*.vtb`, `region.vtb.ru`, `vtbgroup.vtb.com`. |
| `roles/ceph-packages/files/*<ceph_repo_ver>*.deb` | Локальные пакеты `cephadm`; выбирается ровно один файл под `ceph_repo_ver`. |
| `roles/cluster-init/files/*.tar.gz` | Архивы образов для registry на первом mon при **02** (см. `roles/cluster-init/files/README`). |

`seg_fqdn` выбирает AD-домен и какой набор CA ставится. Публичные CA лучше хранить как обычный PEM; если vault-зашифрованы — тот же пароль, что при шифровании.

## Секреты

| Путь | Назначение |
|---|---|
| `secrets/vault.yml` | Vault: пароли/ключи для preflight (`sdsadmin_passwd`, хэши/pubkey по окружению и т.д.). |

## Типы окружения

`environment_type` — одно из `DEV`, `TEST`, `PROD`. Preflight проверяет ОС (Ubuntu noble), обязательные переменные group_vars/vault и (без `force=yes`) отсутствие на хостах текущего плейа учёток администратора из плейбука 04.

## Теги

У большинства ролей есть теги (`preflight`, `network`, `packages`, `ceph`, `sssd`, `certs`, …). Через `--tags` / `--skip-tags` можно сузить прогон, если вы понимаете последствия.
