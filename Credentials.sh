#!/usr/bin/env bash
set -euo pipefail

# Terminal input keeps secrets out of argv, environment variables and settings.
if ! command -v secret-tool >/dev/null; then
    printf '%s\n' 'Install libsecret (secret-tool) and start a Secret Service keyring.'
    read -r -p 'Press Enter / Enter para sair: ' _
    exit 1
fi
if [[ ${LANG:-} == pt* ]]; then
    title='Frigate: credenciais no keyring do sistema'
    user_prompt='Usuário (vazio remove autenticação): '
    pass_prompt='Senha: '
    done_text='Salvo. Clique em Recarregar credenciais no painel.'
else
    title='Frigate: credentials in the system keyring'
    user_prompt='Username (empty removes authentication): '
    pass_prompt='Password: '
    done_text='Saved. Click Reload credentials in the panel.'
fi
printf '%s\n' "$title"
read -r -p "$user_prompt" frigate_user
if [[ -n $frigate_user ]]; then
    read -r -s -p "$pass_prompt" frigate_password
    printf '\n'
    # Store the password first; do not change the username when that fails.
    printf '%s' "$frigate_password" | secret-tool store --label='Noctalia Frigate (password)' service noctalia-frigate key password
    printf '%s' "$frigate_user" | secret-tool store --label='Noctalia Frigate (username)' service noctalia-frigate key username
    unset frigate_password
else
    secret-tool clear service noctalia-frigate key username || [[ $? == 1 ]]
    secret-tool clear service noctalia-frigate key password || [[ $? == 1 ]]
fi
printf '%s\n' "$done_text"
read -r -p 'Enter: ' _
