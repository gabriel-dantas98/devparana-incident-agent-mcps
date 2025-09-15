## 2025-09-11 18:56:44

## TASK LIST - BUILD E DEPLOY BACKSTAGE

### 📋 ANÁLISE INICIAL:
- ✅ Package.json raiz tem: `build:backend` e `build-image`
- ✅ Package.json backend tem: `build-image: docker build ../.. -f Dockerfile --tag backstage`
- ✅ Dockerfile existe em packages/backend/
- ❌ Não existe backstage-deployment.yaml
- ❌ Não existe backstage-ingress.yaml
- ✅ Padrão de ingress estabelecido: `*.localdev.me`

### 1. CRIAR RECURSOS KUBERNETES (Alta Prioridade)
- [x] Criar backstage-deployment.yaml com Deployment e Service
- [x] Criar backstage-ingress.yaml seguindo padrão `backstage.localdev.me`
- [x] Configurar imagem: `localhost:5001/backstage:latest`

### 2. CRIAR SCRIPT BUILD-DEPLOY (Dependência: 1)
- [x] Script `build-backstage.sh` que:
  - Executa yarn build:backend
  - Executa yarn build-image com tag para registry local
  - Faz push para localhost:5001
  - Faz kubectl patch deployment para nova imagem

### 3. INTEGRAR COM SCRIPTS EXISTENTES (Dependência: 1,2)
- [x] Adicionar backstage-ingress.yaml ao kustomization.yaml
- [x] Atualizar setup.sh para aplicar recursos Backstage
- [x] Atualizar get-urls.sh para incluir URL do Backstage
- [x] Atualizar configure-hosts.sh para adicionar backstage.localdev.me
- [x] Atualizar Makefile com comandos build-backstage, restart-backstage, logs-backstage

### 4. VALIDAÇÃO (Dependência: 1,2,3)
- [x] Testar build da imagem
- [x] Testar deploy no cluster  
- [x] Validar acesso via backstage.localdev.me
- [x] Testar workflow completo: build → push → pull → deploy
- [x] Simplificar para banco em memória (PostgreSQL removido)

### ✅ RECURSOS CRIADOS:
- `/cluster/resources/backstage/backstage-deployment.yaml` - Namespace, Deployments (backstage + postgres), Services
- `/cluster/resources/ingress/backstage-ingress.yaml` - Ingress para backstage.localdev.me
- `/cluster/scripts/build-backstage.sh` - Script completo de build e deploy

### 📝 ATUALIZAÇÕES:
- setup.sh: Aplica recursos do Backstage e inclui validação
- get-urls.sh: Lista URLs do Backstage
- configure-hosts.sh: Adiciona backstage.localdev.me aos hosts
- ingress/kustomization.yaml: Inclui backstage-ingress.yaml
- Makefile: Comandos build-backstage, restart-backstage, logs-backstage, port-forward atualizado
