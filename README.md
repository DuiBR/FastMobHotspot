# FastMob Hotspot Firewall

Firewall para Android com root que restringe a Internet compartilhada pelo hotspot.

Com o firewall ativado, os aparelhos conectados ao hotspot sÃ³ conseguem acessar os servidores e proxies necessÃ¡rios para conectar ao aplicativo FASTMOB VPN. O restante do trÃ¡fego Ã© bloqueado atÃ© que a VPN seja conectada.

## Requisitos

- Android com root funcionando.
- Magisk ou outro gerenciador de root compatÃ­vel.
- Termux instalado.
- Acesso root concedido ao Termux.
- Hotspot Wi-Fi disponÃ­vel no aparelho.

> Atualmente, o hotspot deve ser ligado manualmente antes de executar `fastmob-on`.

---

## InstalaÃ§Ã£o rÃ¡pida

Abra o Termux e cole este comando completo:

```bash
pkg update -y && pkg install curl -y && curl -fsSL "https://raw.githubusercontent.com/DuiBR/FastMobHotspot/main/fastmob-installer.sh?nocache=$(date +%s)" -o ~/fastmob-installer.sh && chmod +x ~/fastmob-installer.sh && bash ~/fastmob-installer.sh
```

Quando o Magisk solicitar acesso root para o Termux, toque em **Permitir**.

Depois da instalaÃ§Ã£o, feche e abra o Termux caso os comandos ainda nÃ£o sejam reconhecidos.

---

## InstalaÃ§Ã£o passo a passo

### 1. Atualize o Termux e instale o curl

```bash
pkg update -y
pkg install curl -y
```

### 2. Baixe o instalador

```bash
curl -fsSL "https://raw.githubusercontent.com/DuiBR/FastMobHotspot/main/fastmob-installer.sh?nocache=$(date +%s)" -o ~/fastmob-installer.sh
```

### 3. DÃª permissÃ£o de execuÃ§Ã£o

```bash
chmod +x ~/fastmob-installer.sh
```

### 4. Execute o instalador

```bash
bash ~/fastmob-installer.sh
```

---

## Comandos disponÃ­veis

### Detectar o hotspot

Ligue o hotspot e execute:

```bash
fastmob-detect
```

O comando identifica e salva automaticamente a interface usada pelo hotspot.

### Ativar o firewall

Primeiro ligue o hotspot. Depois execute:

```bash
fastmob-on
```

Com o firewall ativado:

- A navegaÃ§Ã£o normal dos clientes fica bloqueada.
- O DNS de inicializaÃ§Ã£o permanece liberado.
- Os servidores FASTMOB VPN permanecem acessÃ­veis.
- Os proxies FASTMOB permanecem acessÃ­veis somente em TCP/80.
- O trÃ¡fego IPv6 do hotspot Ã© bloqueado para evitar bypass.

### Consultar o status

```bash
fastmob-status
```

O status mostra:

- VersÃ£o instalada.
- Interface do hotspot.
- Estado do firewall.
- IPs permitidos.
- Contadores de pacotes aceitos e bloqueados.
- Estado do bloqueio IPv6.

### Desativar o firewall

```bash
fastmob-off
```

Esse comando remove somente as regras criadas pelo FASTMOB. Depois disso, o hotspot volta a compartilhar a Internet normalmente.

---

## Uso diÃ¡rio

### Ativar o modo FASTMOB

```bash
fastmob-on
```

### Verificar se estÃ¡ ativo

```bash
fastmob-status
```

### Desativar e liberar o hotspot normalmente

```bash
fastmob-off
```

### Detectar novamente a interface

```bash
fastmob-detect
```

---

## Atualizar para a versÃ£o mais recente

Cole este comando no Termux:

```bash
fastmob-off && curl -fsSL "https://raw.githubusercontent.com/DuiBR/FastMobHotspot/main/fastmob-installer.sh?nocache=$(date +%s)" -o ~/fastmob-installer.sh && chmod +x ~/fastmob-installer.sh && bash ~/fastmob-installer.sh
```

Depois confira a versÃ£o instalada:

```bash
fastmob-status
```

---

## ConfiguraÃ§Ã£o atual do firewall

### Servidores VPN permitidos

```text
144.22.139.151
163.176.118.248
```

### Proxies permitidos somente em TCP/80

```text
104.26.5.32
104.17.70.206
104.17.72.206
```

### DNS de inicializaÃ§Ã£o

```text
UDP/53
TCP/53
```

Todos os outros destinos encaminhados pelo hotspot sÃ£o bloqueados enquanto o `fastmob-on` estiver ativo.

---

## Teste de funcionamento

1. Ligue o hotspot do Android.
2. Execute `fastmob-on` no Termux.
3. Conecte outro aparelho ao hotspot.
4. Sem a VPN, tente abrir um site: ele deve permanecer bloqueado.
5. Abra o aplicativo FASTMOB VPN no aparelho conectado.
6. Conecte a VPN.
7. Execute `fastmob-status` no aparelho que fornece o hotspot.

Os contadores dos servidores ou proxies permitidos devem aumentar durante a conexÃ£o.

Para acompanhar as regras em tempo real:

```bash
su -c 'watch -n 1 iptables -L FASTMOB_ONLY -n -v --line-numbers'
```

Para sair do acompanhamento, pressione `CTRL + C`.

---

## SoluÃ§Ã£o de problemas

### `fastmob-on: command not found`

Feche e abra novamente o Termux. Se continuar, reinstale:

```bash
bash ~/fastmob-installer.sh
```

### Erro de acesso root

Teste o root:

```bash
su -c id
```

O resultado deve conter:

```text
uid=0(root)
```

Caso o Magisk mostre uma solicitaÃ§Ã£o, conceda acesso root ao Termux.

### Hotspot nÃ£o detectado

Ligue o hotspot e execute:

```bash
fastmob-detect
```

Depois ative novamente:

```bash
fastmob-on
```

### A VPN nÃ£o conecta

Primeiro consulte os contadores:

```bash
fastmob-status
```

Se apenas a regra `DROP` aumentar, o aplicativo pode estar usando outro servidor, proxy, API ou porta que ainda nÃ£o foi adicionada Ã  configuraÃ§Ã£o.

Para liberar temporariamente o hotspot durante o diagnÃ³stico:

```bash
fastmob-off
```

### A Internet continua funcionando sem VPN

Confira se o firewall estÃ¡ ativo:

```bash
fastmob-status
```

Confira tambÃ©m se o offload do tethering estÃ¡ desativado:

```bash
su -c 'settings get global tether_offload_disabled'
```

O resultado esperado Ã©:

```text
1
```

---

## Remover completamente

Execute este bloco no Termux:

```bash
fastmob-off 2>/dev/null
rm -f "$PREFIX/bin/fastmob-on"
rm -f "$PREFIX/bin/fastmob-off"
rm -f "$PREFIX/bin/fastmob-status"
rm -f "$PREFIX/bin/fastmob-detect"
su -c 'rm -rf /data/adb/fastmob-firewall'
rm -f ~/fastmob-installer.sh
```

Depois feche e abra novamente o Termux.

---

## SeguranÃ§a

O script cria cadeias prÃ³prias no `iptables` e no `ip6tables`. Ele nÃ£o apaga as regras originais do Android.

Mesmo com o hotspot aberto, o servidor VPN deve continuar exigindo autenticaÃ§Ã£o, UUID, senha, token ou outra credencial individual. O firewall limita os destinos acessÃ­veis, mas nÃ£o substitui a autenticaÃ§Ã£o do servidor.

## VersÃ£o atual

```text
2.1.0-proxy
```
