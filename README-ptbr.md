# cPanel DNS Audit (`cp-dns-audit.sh`)

![Capa do cPanel DNS Audit](./cpanel-dns-audit-cover.webp)

[![Versão](https://img.shields.io/badge/version-2.0.0-blue.svg)](./cp-dns-audit.sh)
[![Licença](https://img.shields.io/badge/license-Apache--2.0-green.svg)](./LICENSE)
[![Plataforma](https://img.shields.io/badge/platform-Linux%20%7C%20cPanel%20%2F%20WHM%20%7C%20BIND9-orange.svg)](#requisitos)

> 🇺🇸 **[Read in English (README.md)](./README.md)**

O **cPanel DNS Audit** (`cp-dns-audit.sh` v2.0.0) é uma ferramenta CLI em Bash + Python3 (somente biblioteca padrão) para auditoria profunda de zonas DNS BIND9 / cPanel (`/var/named/*.db`). Ele valida a sintaxe de cada zona com `named-checkzone`, extrai registros MX, rastreia registros `mail` (`A` e `CNAME` com resolução de IP e detecção de loop), cruza `/etc/localdomains` e `/etc/remotedomains` para identificar erros silenciosos de roteamento (`ROUTING_MISMATCH`) e verifica a presença de SPF, DKIM e DMARC.

---

## Funcionalidades

- **Validação de Sintaxe BIND9:** Executa `named-checkzone -q` automaticamente quando disponível no servidor para detectar falhas de sintaxe, SOA ou NS ausentes.
- **Auditoria de Roteamento de E-mail:** Cruza o MX primário (Google Workspace, Microsoft 365, Zoho, Proton, entre outros) com `/etc/localdomains` e `/etc/remotedomains`, alertando sobre `ROUTING_MISMATCH` antes que mensagens locais sejam perdidas.
- **Rastreamento de CNAME e Loops:** Resolve o endereço IP real de destinos `CNAME` do subdomínio `mail` (ou roda offline com `--no-dns-resolve`) e sinaliza loops (`CNAME_LOOP`).
- **Cobertura de Autenticação de E-mail:** Verifica SPF (`v=spf1`), DKIM (`_domainkey`) e DMARC (`_dmarc` / `v=DMARC1`) em cada zona (`SKD`).
- **Filtros e Formatos Estruturados:** Audita todas as zonas (`--all-zones`) ou um único domínio (`-D`), filtra apenas zonas com problemas (`-e, --only-issues`) e exporta em `table`, `json` ou `csv` para tela, arquivo (`-f`) ou e-mail (`-m`).
- **Exit Codes para Automação:** Retorna `0` quando todas as zonas estão limpas, `1` em erro de uso/execução e `2` quando existem alertas ou falhas críticas.

---

## Requisitos

- Linux com Bash 4.0+ e Python 3.6+ (somente biblioteca padrão, zero dependências externas)
- Diretório de zonas BIND / cPanel (padrão `/var/named`)
- Opcional: `named-checkzone` (validação de sintaxe), `mail` ou `sendmail` (envio de relatório via `-m`)

---

## Instalação

```bash
git clone https://github.com/sr00t3d/cpanel-dns-audit.git
cd cpanel-dns-audit
chmod +x cp-dns-audit.sh
```

---

## Como usar

```bash
# Auditar todas as zonas em /var/named
sudo ./cp-dns-audit.sh --all-zones

# Auditar um único domínio
sudo ./cp-dns-audit.sh -D example.com

# Exibir apenas zonas com falhas ou alertas
sudo ./cp-dns-audit.sh --only-issues

# Exportar auditoria completa em JSON para arquivo
sudo ./cp-dns-audit.sh -o json -f /tmp/dns-audit.json

# Exportar em CSV (modo offline sem resolução DNS de CNAME)
sudo ./cp-dns-audit.sh --no-dns-resolve -o csv > dns-audit.csv

# Auditar diretório específico e enviar relatório por e-mail
sudo ./cp-dns-audit.sh -d /var/named -m ops@example.com
```

### Opções da CLI

| Opção | Descrição |
| :--- | :--- |
| `--all-zones` | Audita todos os arquivos `*.db` em `--dir` (padrão) |
| `-d, --dir <caminho>` | Diretório de zonas BIND/Named (padrão: `/var/named`) |
| `-D, --domain <domínio>` | Audita apenas o arquivo de zona de um domínio |
| `-e, --only-issues` | Exibe apenas zonas com erro de sintaxe, MX, roteamento ou autenticação |
| `--no-dns-resolve` | Pula a resolução DNS em tempo real de alvos `CNAME` |
| `-o, --output <fmt>` | Formato de saída: `table` (padrão), `json`, `csv` |
| `-f, --file <caminho>` | Salva o relatório em arquivo |
| `-m, --email <endereço>` | Envia o relatório via `mail` ou `sendmail` |
| `-q, --quiet` | Suprime mensagens de progresso |
| `--no-color` | Desativa cores ANSI |
| `-V, --version` | Exibe a versão e encerra |
| `-h, --help` | Exibe a ajuda e encerra |

---

## Exemplo de Saída Real

Capturado em container AlmaLinux 8.10 / cPanel auditando 3 zonas (e-mail local saudável, conflito de roteamento com Google Workspace e zona com loop de CNAME sem MX):

```text
============================================================================================================================
 CPANEL DNS AUDIT v2.0.0 - [cpanel-test.local] | Dir: /tmp/dns-audit-fixture | Zones: 3
============================================================================================================================
DOMAIN                     | ROUTING | PRIMARY MX                   | MAIL/IP                | AUTH  | STATUS   | ISSUES
----------------------------------------------------------------------------------------------------------------------------
broken.example.com         | UNKNOWN | -                            | CNAME:LOOP             | ---   | CRITICAL | NO_MX,CNAME_LOOP,NO_SPF,NO_DMARC
healthy.example.com        | LOCAL   | mail.healthy.example.com     | A:192.0.2.10           | SKD   | OK       | clean
workspace.example.com      | LOCAL   | aspmx.l.google.com           | CNAME:142.250.139.121  | S--   | CRITICAL | ROUTING_MISMATCH,NO_DMARC
============================================================================================================================
 Summary: 3 zone(s) | OK: 1 | WARN: 0 | CRITICAL: 2 | Auth Legend: S=SPF K=DKIM D=DMARC
============================================================================================================================
```

---

## Licença

Distribuído sob a [Licença Apache-2.0](./LICENSE).
