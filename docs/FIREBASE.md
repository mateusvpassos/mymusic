# Ligar a nuvem (Firebase) — passo a passo

Uns 10 minutos, tudo no navegador. No fim você me manda dois blocos de
configuração (Android e Web) e eu coloco no app e no editor web.

## 1. Criar o projeto em cima do projeto Google que já existe

1. Abra https://console.firebase.google.com e clique em **Criar um projeto**
   (ou "Adicionar projeto").
2. Na tela do nome, clique em **"Adicionar o Firebase a um projeto do Google Cloud"**
   e escolha o projeto que o app já usa para o Drive (nº **333951307134**).
   Assim o login do Google que já funciona no tablet e no web continua valendo.
3. Google Analytics: **desligado** (não precisa). Concluir.

## 2. Login com Google

1. Menu da esquerda → **Criação** (Build) → **Authentication** → **Vamos começar**.
2. Aba **Método de login** → **Google** → **Ativar** → escolha seu e-mail de suporte → **Salvar**.
3. Ainda em Authentication → **Configurações** → **Domínios autorizados**:
   confira se `localhost` está na lista (o editor web roda nele).

## 3. Banco de dados

1. **Criação** → **Firestore Database** → **Criar banco de dados**.
2. Local: **southamerica-east1 (São Paulo)**. Modo: **produção**. Criar.
3. Aba **Regras**: apague o que estiver lá, cole o conteúdo de
   [`firebase/firestore.rules`](../firebase/firestore.rules) e clique em **Publicar**.
   (São elas que garantem dono, permissão e sugestão no servidor.)

## 4. Registrar o app Android

1. Engrenagem ⚙ → **Configurações do projeto** → em "Seus apps", ícone do **Android**.
2. Nome do pacote: `com.mvini.mymusic`. Apelido: MyMusic. (SHA-1 não precisa
   agora.) **Registrar app**.
3. Baixe o **google-services.json** e me mande (ou copie os valores
   `mobilesdk_app_id`, `current_key` e `project_id`). Pode pular os outros passos do assistente.

## 5. Registrar o editor web

1. Mesma tela → **Adicionar app** → ícone **Web** (`</>`). Apelido: MyMusic web.
   **Não** marque Firebase Hosting. Registrar.
2. Copie o bloco `const firebaseConfig = { ... }` que aparece e me mande.

## 6. Quem vai usar

O app está em "modo de teste" no Google: cada pessoa precisa estar na lista de
usuários de teste (até 100).

- https://console.cloud.google.com → projeto 333951307134 → **APIs e serviços** →
  **Tela de consentimento OAuth** (ou "Público") → **Usuários de teste** → adicionar o
  e-mail Google de cada pessoa do grupo.

## Depois (eu faço com você)

1. Coloco as configurações, gero o app e instalo no tablet.
2. No tablet: ☁ (barra de cima) → **Entrar com Google** → **Criar grupo** (dê o nome
   que quiser) → **Enviar para o grupo**: suas músicas e repertórios vão para a nuvem
   com você como dono. O Drive continua como backup.
3. Convide as pessoas pelo e-mail na mesma tela.

Custo: plano gratuito (Spark), sem cartão. O uso de vocês fica muito abaixo do limite.
