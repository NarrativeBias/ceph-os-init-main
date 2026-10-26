# ceph-os-init

Ansible-плейбуки для подготовки серверов Ubuntu 20.04/24.04 по нашим стандартам и практикам c возможностью дальнейшего деплоя Ceph на них.

## Использование

Запускать из корня репозитория. Инвентарь — один файл; рядом с ним лежит `group_vars/`.

```bash
# 0) Разовая подготовка (на каждый инвентарь)
cp group_vars/deployment.yaml.sample <inventory_dir>/group_vars/deployment.yaml  # заполнить
cp group_vars/etc-hosts.example <inventory_dir>/group_vars/etc-hosts              # заполнить
# В этом репозитории: secrets/vault.yml
# CA: roles/ca-certs/files/{test,dev,prod}/*.crt
# Ceph: roles/ceph-packages/files/*<ceph_version>*.deb
#   и для нового кластера registry-images/*.tar.gz

# 1) Только подготовка ОС (без Ceph); [deployment] = хосты прогона
ansible-playbook playbooks/01-prepare-srv.yml -i <inventory> -e srv=deployment --ask-vault-pass

# 2) Новый кластер Ceph ([deployment] = весь [vse])
ansible-playbook playbooks/01-prepare-srv.yml   -i <inventory> -e srv=deployment --ask-vault-pass
ansible-playbook playbooks/02-prepare-ceph.yml  -i <inventory> -e srv=deployment -e cluster_action=init --ask-vault-pass
# (02: registry + cephadm bootstrap + post-bootstrap on the first mon)
ansible-playbook playbooks/03-deploy-ceph.yml   -i <inventory> -e srv=deployment -e cluster_action=init --ask-vault-pass
# (03: images/keys, host add, agents, mon/mgr)
ansible-playbook playbooks/04-deploy-osds.yml   -i <inventory> -e srv=deployment -e cluster_action=init --ask-vault-pass
# (04: NVMe namespaces on [osds]; later OSD deploy)
# … init-плейбук группы UNIX (вне этого репозитория) …
ansible-playbook playbooks/05-post-init.yml     -i <inventory> -e srv=deployment --ask-vault-pass
# … чеклист ПНР …
ansible-playbook playbooks/06-finish-pnr.yml    -i <inventory> -e srv=deployment --ask-vault-pass

# 3) Расширение ([deployment] = только новые; они же в [vse] вместе со старыми)
ansible-playbook playbooks/01-prepare-srv.yml   -i <inventory> -e srv=deployment --ask-vault-pass
ansible-playbook playbooks/02-prepare-ceph.yml  -i <inventory> -e srv=deployment -e cluster_action=extend --ask-vault-pass
ansible-playbook playbooks/03-deploy-ceph.yml   -i <inventory> -e srv=deployment -e cluster_action=extend --ask-vault-pass
ansible-playbook playbooks/04-deploy-osds.yml   -i <inventory> -e srv=deployment -e cluster_action=extend --ask-vault-pass
# … init-плейбук группы UNIX (вне этого репозитория) …
ansible-playbook playbooks/05-post-init.yml     -i <inventory> -e srv=deployment --ask-vault-pass
# … чеклист ПНР …
ansible-playbook playbooks/06-finish-pnr.yml    -i <inventory> -e srv=deployment --ask-vault-pass

# 4) Уже развёрнутые хосты: только CA + SSSD LDAPS
ansible-playbook playbooks/existing-servers/enable-sssd-tls.yml -i <inventory> -e srv=<group> --ask-vault-pass
```

`--ask-vault-pass` нужен, если расшифровываются `secrets/vault.yml` или vault-зашифрованные сертификаты. Если ничего не vault-зашифровано — можно не указывать.

Опционально: `-e force=yes` обходит остановку preflight, когда на хосте уже есть учётка администратора (*sadm) из плейбука 06.

---

## Назначение

Репозиторий решает две связанные, но разные задачи:

1. **Подготовка хостов** — Ubuntu **20.04 (focal)** или **24.04 (noble)** (`ubuntu_version` в deployment.yaml; кодовое имя выводится автоматически): сеть, репозитории, пакеты, NTP, тюнинг ОС, пользователи. Для этого достаточно `01-prepare-srv`; Ceph при этом ставить не обязательно.
2. **Развёртывание Ceph** — bootstrap (`02`), join/агенты/mon/mgr (`03`), диски/OSD (`04`). Дальше — внешний init группы UNIX, наш `05-post-init`, чеклист ПНР и финальный `06-finish-pnr`.

| Плейбук | Назначение |
|---|---|
| `01-prepare-srv` | Только ОС: DNS/hostname, `/etc/hosts`, apt-репозитории, пакеты, dnsmasq, NTP, os-tune, RAID CLI, root PV, unix-пользователи. Без `cluster_action`. |
| `02-prepare-ceph` | Ceph-пользователи, локальный `cephadm` .deb, podman, registry (init), `cephadm bootstrap` + post-bootstrap на первом mon при init (`cluster_network`). |
| `03-deploy-ceph` | Pull образов, ключ cephorch, `orch host add` (IP ∈ `public_networks`), crash/node-exporter/ceph-exporter, mon/mgr по `[mons]` с ожиданием running==size. |
| `04-deploy-osds` | На `{{ srv }}:&osds`: NVMe → 2 namespaces (`osd_nvme_namespace_sizes`), затем `ceph orch apply` OSD-спеков (nvme0n1–7n1 + n2). |
| `05-post-init` | После init-плейбука группы UNIX: `/etc/hosts`, `/etc/ceph/cmdb.ini`, пользователи/NTP, info по кластеру Ceph, CA (с очисткой старых), SSSD LDAPS, Zabbix, shell prompt. |
| `06-finish-pnr` | Последний шаг подготовки хостов после чеклиста ПНР: продакшен-админы, IPMI, перенос s3-init. |
| `existing-servers/enable-sssd-tls` | CA-доверие и `ad_use_ldaps` на уже развёрнутых хостах (без полного 05). |

Роли в `roles/`; в `ansible.cfg` заданы `roles_path = ./roles` и лог в `~/ansible.log`.

## Инвентарь и группы

Нужен **один файл инвентаря** (при init он копируется на первый mon). Целевой прогон всегда: `-e srv=deployment`.

| Группа | Назначение |
|---|---|
| `[deployment]` | Хосты **текущего** прогона (и получатели `group_vars/deployment.yaml`). Init → те же, что `[vse]`; extend → только добавляемые. |
| `[vse]` | Все серверы кластера (при extend — старые + новые). |
| `[mons]`, `[osds]`, … | Ролевые группы. Первый хост в `[mons]` (порядок в инвентаре) — Ansible-контроллер кластера и хост локального registry при init. |

- **Init:** `-e srv=deployment -e cluster_action=init` — `[deployment]` и `[vse]` совпадают (весь кластер).
- **Extend:** `-e srv=deployment -e cluster_action=extend` — в `[deployment]` только новые; они же перечислены в `[vse]` вместе с уже работающими. Плейбук к существующим (в `[vse]`, но не в `[deployment]`) не ходит.

`roles/cluster-scope` проверяет это на контроллере до подключения к серверам и публикует `cluster_new_hosts`, `cluster_existing_hosts`, `cluster_hosts` для ролей, которым нужен полный список имён.

## Файлы рядом с инвентарём

| Путь | Назначение |
|---|---|
| `group_vars/deployment.yaml` | Из `group_vars/deployment.yaml.sample`: `local_registry`, `ceph_version`, `ubuntu_version` (`20.04`/`24.04`), `seg_fqdn`, `environment_type` и др. Подхватывается для хостов группы `[deployment]`. |
| `group_vars/etc-hosts` | Из `group_vars/etc-hosts.example`: строки `IP FQDN короткое_имя`. Ставится в 01 и снова в 05. |
| `/etc/ceph/cmdb.ini` | Пишется ролью `cmdb-ini` в 05: `CLUSTER_NAME` ← `cluster_name`; `HOST_REAL_SIZE` ← `fs_cmdb_size` на `[osds]`, иначе `0`. |

## Файлы в ролях (общие для инвентарей)

| Путь | Назначение |
|---|---|
| `roles/ca-certs/files/test/*.crt` | Цепочка CA для `test.vtb.ru`. |
| `roles/ca-certs/files/dev/*.crt` | Цепочка CA для `corp.dev.vtb`. |
| `roles/ca-certs/files/prod/*.crt` | Цепочка CA для `cde.vtb`, `inet.vtb`, `cn-*.vtb`, `region.vtb.ru`, `vtbgroup.vtb.com`. |
| `roles/ceph-packages/files/cephadm_*<ceph_version>*_amd64.deb` | Локальный `cephadm` (например `cephadm_20.2.4-1noble_amd64.deb`); выбор по `ceph_version`. |
| `roles/podman/files/podman-pkgs/*.deb` | (только 20.04) набор podman 3.4.2 + deps; на 24.04 podman из apt. |
| `registry-images/*.{tar.gz,tar.zst}` | (корень репо) архивы образов для registry на первом mon при **02** (см. `registry-images/README`). |

`seg_fqdn` выбирает AD-домен и какой набор CA ставится. Публичные CA лучше хранить как обычный PEM; если vault-зашифрованы — тот же пароль, что при шифровании.

## Секреты

| Путь | Назначение |
|---|---|
| `secrets/vault.yml` | Vault: пароли/ключи для preflight (`sdsadmin_passwd`, хэши/pubkey по окружению и т.д.). |

## Типы окружения

`environment_type` — `DEV`/`TEST`/`PROD`. Preflight проверяет `ubuntu_version` (и совпадение с хостом), совместимость `ceph_version` с ОС, обязательные group_vars/vault и (без `force=yes`) отсутствие учёток администратора из плейбука 06.

Матрица Ceph ↔ ОС: **17.2.6 / 18.2.7 → 20.04**; **19.2.6 / 20.2.4 → 24.04** (проверка по префиксу major: `17.`/`18.` vs `19.`/`20.`).

## Теги

У большинства ролей есть теги (`preflight`, `network`, `packages`, `ceph`, `sssd`, `certs`, …). Через `--tags` / `--skip-tags` можно сузить прогон, если вы понимаете последствия.
