# Ctrus Recovery Worker

Cloudflare Worker que substitui o código de desbloqueio fixo ("3530-CtrusUnblock!") por
códigos únicos por instalação e de utilização única.

- `POST /request-code` `{ deviceId }` -> `{ code }` (válido 15 min, idempotente enquanto válido)
- `POST /verify-code` `{ deviceId, code }` -> `{ valid, recentUnlockCount }` (código é apagado após uso, mesmo se inválido 5x seguidas)
- `GET /` -> página HTML onde a pessoa cola o Device ID e recebe o código

Não guarda nenhuma informação pessoal — o `deviceId` é só um UUID aleatório gerado no telemóvel.

## Deploy (primeira vez)

Estes passos exigem a tua conta Cloudflare (onde já está registado o domínio `ctrus.net`).

```bash
cd CtrusRecoveryWorker
npm install

# Autenticar com a tua conta Cloudflare (abre o browser)
npx wrangler login

# Criar o KV namespace onde os códigos ficam guardados
npx wrangler kv namespace create RECOVERY_CODES
```

O comando anterior imprime algo como:

```
[[kv_namespaces]]
binding = "RECOVERY_CODES"
id = "abcd1234..."
```

Copia esse `id` para o `wrangler.toml` (substitui `REPLACE_ME_AFTER_RUNNING_WRANGLER_KV_NAMESPACE_CREATE`).

```bash
npx wrangler deploy
```

## Ligar o domínio `recover.ctrus.net`

Na dashboard da Cloudflare:

1. **Workers & Pages** -> `ctrus-recovery` -> **Settings** -> **Domains & Routes**
2. **Add** -> **Custom Domain** -> escreve `recover.ctrus.net`
3. Confirma. A Cloudflare trata do DNS automaticamente porque o domínio já está na tua conta.

Depois disto, `https://recover.ctrus.net` já serve a página de recuperação e os dois endpoints.

## Deploys seguintes

```bash
cd CtrusRecoveryWorker
npx wrangler deploy
```

## Testar

```bash
curl -X POST https://recover.ctrus.net/request-code \
  -H "content-type: application/json" \
  -d '{"deviceId":"teste-123"}'

curl -X POST https://recover.ctrus.net/verify-code \
  -H "content-type: application/json" \
  -d '{"deviceId":"teste-123","code":"CODIGO-RECEBIDO"}'
```
