# Como injetar as chaves dos agentes no workspace (sem versionar nada)

O `.env.local` fica so na sua maquina (nunca commitar). No Dev Spaces ele vira um
Secret do Kubernetes que e montado como variaveis de ambiente em todos os containers.

```bash
oc login --token=<token> --server=https://api.<cluster>:6443

# Secret no namespace do usuario (ex.: robson-neto-devspaces)
oc create secret generic agents-env --from-env-file=.env.local -n <namespace>

# Label/annotation para o DevWorkspace montar como env vars
oc label secret agents-env controller.devfile.io/mount-to-devworkspace=true controller.devfile.io/watch-secret=true -n <namespace>
oc annotate secret agents-env controller.devfile.io/mount-as=env -n <namespace>
```

Reinicie o workspace depois de criar ou alterar o Secret.

Notas:
- Linhas com valor vazio no `.env.local` tambem viram variaveis vazias; apague as que nao usar.
- Sem chaves, os agentes podem apontar para o LLM local: `LOCAL_LLM_BASE_URL` (`http://localhost:8080/v1`).
- Adicione `.env.local` e `.env` ao `.gitignore`.
