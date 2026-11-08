# 💰 FinSense macOS

<div align="center">

![macOS Native](https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue?style=for-the-badge&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.10%2B-orange?style=for-the-badge&logo=swift)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-indigo?style=for-the-badge)
![IA Local](https://img.shields.io/badge/AI-100%25%20Local%20LLM-success?style=for-the-badge&logo=openai)
![Privacidade](https://img.shields.io/badge/Privacidade-Zero%20Cloud%20%7C%20100%25%20Offline-black?style=for-the-badge)

**Aplicativo nativo para macOS de gestão financeira pessoal e empresarial completa, com inteligência artificial 100% local, análise automatizada de extratos/relatórios e privacidade absoluta.**

</div>

---

## 📌 Sobre o Projeto

O **FinSense** é um aplicativo de alta performance desenvolvido exclusivamente para o ecossistema Apple macOS. Projetado para quem busca organização financeira profunda sem abrir mão da sua privacidade, o sistema opera **100% offline**: todos os seus dados, contas, transações e dívidas residem exclusivamente no seu Mac, sem envio de informações para nuvens de terceiros.

O diferencial revolucionário é a **IA Local Embarcada**: integrada a modelos de linguagem (LLMs) executados diretamente no hardware da sua máquina (via Hugging Face e MLX/GGUF). A IA lê extratos bancários em PDF ou texto bruto, categoriza despesas e receitas de forma inteligente, interpreta contratos de financiamento e responde perguntas analíticas sobre suas finanças em linguagem natural.

---

## 🚀 Principais Funcionalidades

### 📊 1. Dashboard e Visão Estratégica
- **Modos de Visualização**:
  - **Visão Mensal**: Navegação mês a mês com resumos de receitas, despesas, saldo operacional e saldo acumulado.
  - **Visão Anual**: Visão macro consolidada com projeções de receitas, parcelamentos e recorrências até o último dia do ano.
- **Total de Dívidas & Compromissos**: Visão centralizada das obrigações futuras (dívidas em aberto, cartões, empréstimos e financiamentos).
- **Detalhamento por Categorias**: Gráficos e resumos de gastos percentuais e nominais por categoria.
- **Previsões & Tetos do Mês (Orçamento por Envelopes Dinâmicos)**:
  - Definição rápida de limites mensais para categorias variáveis (ex: Combustível, Alimentação, Lazer) com opção de recorrência automática (*"Repetir esta previsão para os próximos meses"*).
  - Desacoplamento total do extrato real: impacta o **Saldo Projetado no Mês** apenas pelo saldo remanescente ($P_{\text{restante}} = \max(0, T_{\text{estimado}} - G_{\text{real}})$), abatendo despesas reais em tempo real sem gerar lançamentos fictícios ou duplicar saídas.
  - Acompanhamento visual com barras de progresso e indicadores de status (**Normal** `< 80%`, **Alerta** `80%–100%` e **Estourado** `> 100%` exibindo o excedente), além de integração com comandos em linguagem natural via Chat IA Local.
- **Status da IA Local**: Indicador dinâmico no topo informando o modelo LLM ativo e atalhos rápidos.

### 💳 2. Gestão Completa de Transações
- **Vistas Especializadas**:
  - **Todas as Transações**: Fluxo de caixa completo.
  - **Despesas**: Cards de *Total de Despesas* e *Total Pendente*.
  - **Receitas**: Cards de *Total Recebido* e *À Receber*.
- **Data Inteligente**: Ao clicar em *"Nova Receita"* ou *"Nova Despesa"*, o sistema preenche a data apontando automaticamente para o mês filtrado.
- **Tipos de Lançamento**:
  - **Pagamento Único**: Despesas ou receitas avulsas.
  - **Parcelado**: Define valor total e número de parcelas, gerando automaticamente os lançamentos mensais futuros.
  - **Repetido**: Replica o mesmo valor por $N$ meses consecutivos.
  - **Recorrente**: Ideal para assinaturas e contas fixas (Netflix, Wellhub, água, energia, aluguel), com frequências personalizadas: diária, semanal, mensal ou anual.
- **Edição em Série Inteligente**: Ao alterar o valor ou dados de uma parcela/recorrência, escolha o escopo do ajuste:
  - *Somente nesta transação*
  - *Em todas as ocorrências*
  - *Desta transação em diante (futuras)*
- **Exclusão em Série com Segurança**:
  - *Remover somente esta*
  - *Remover todas*
  - *Remover esta e as pendentes/futuras*
- **Controle de Pagamentos**:
  - Confirmação visual para marcar ou desfazer pagamentos.
  - Ao pagar uma conta com data futura, o sistema pergunta e move automaticamente a transação para a data atual.
  - Opção *"Ignorar no consolidado"* para registrar lançamentos sem impactar o saldo das contas.
- **Organização e Filtros**:
  - Ordenação por: *Data Crescente*, *Data Decrescente*, *Valor Crescente* e *Valor Decrescente*.
  - Toggle **"Agrupar por dia"** com memorização persistente (`@AppStorage`), exibindo cabeçalhos diários com entradas, saídas e saldo líquido do dia.

### 🤖 3. Importação Inteligente com IA Local
- **Botão Unificado "Importar"**: Presente em todas as telas principais com interface consistente.
- **Entrada Dupla**:
  - *Upload de Arquivo*: Seleciona documentos PDF, CSV ou TXT do Mac.
  - *Caixa de Texto*: Permite digitar ou colar relatórios e listagens soltas de transações. Inicia recolhida por padrão e salva a última escolha do usuário.
- **Separação Rigorosa de Contexto**:
  - Importação de transações aceita apenas receitas e despesas (ignora seções de dívidas).
  - Importação de dívidas aceita exclusivamente cartões e dívidas em aberto.
- **Revisão Item a Item Pré-Importação**:
  - Lista de itens encontrados com permissão para editar título, valor, data, categoria manual e recorrência, além de exclusão individual antes de confirmar.
- **Anti-Duplicação**: Identifica transações já registradas e importa somente lançamentos novos.

### 🛑 4. Módulo de Dívidas (Cartões e Débitos)
- Aba dedicada para dívidas em atraso e cartões de crédito.
- Visualização em cartões com valor original, valor de negociação e data.
- **Fluxo de Negociação e Quitação**:
  - Permite informar o valor negociado e a conta de origem dos fundos.
  - Cria automaticamente a transação de despesa paga e remove o card da listagem.
- Análise de dívidas pela IA Local via chat.

### 📑 5. Empréstimos e Financiamentos
- Suporte a Empréstimos (Consignado, Pessoal) e Financiamentos (Imóvel, Carro).
- **Início Retroativo sem Poluição**: Define a data de formalização original no passado; a aplicação calcula o contrato integralmente mas gera apenas as transações das parcelas futuras a partir de hoje.
- **Leitor de Documentos Bancários via IA**: Extrai dados de contratos da Caixa Econômica, Santander e outros bancos a partir de PDFs ou texto copiado.
- **Cálculo Preciso de Quitação**:
  - Calcula a descapitalização a valor presente com base na taxa de juros efetiva.
  - Garante que a projeção de quitação nunca exceda o saldo devedor teórico.
- **Amortização e Quitação Antecipada**: Ajusta o saldo devedor ou reduz parcelas.
- **Exclusão em Cascata**: Ao excluir um empréstimo ou financiamento, todas as transações vinculadas são removidas automaticamente.

### 📈 6. Investimentos
- Cadastro por grupos e ativos (CDB, Caixinhas, Ações, FIIs, Tesouro).
- Registro de aportes com débito direto da conta bancária de origem.
- Opção *"Exibir no consolidado"* por investimento para compor ou não o patrimônio total.

### ⚙️ 7. Configurações & Personalização
- **Gerenciador de IA Local**: Download, exclusão e troca de modelos da Hugging Face com chave de API opcional.
- **Chat com IA Local (`Cmd + K`)**: Assistente financeiro treinado com acesso seguro e restrito à base local de dados.
- **Reordenação Drag & Drop**: Arraste e solte contas e categorias para reordenar sua exibição.
- **Gestão de Contas e Categorias**: Suporte a ícones nativos do sistema e logotipos personalizados anexados do Mac.
- **Atalhos Globais de Teclado**:
  - `Cmd + 1` até `Cmd + 6`: Navegação rápida entre as seções.
  - `Cmd + K`: Acesso instantâneo ao Chat com a IA Local.

---

## 🛠️ Tecnologias Utilizadas

- **Linguagem**: Swift 5.10+
- **Interface**: SwiftUI 5 + AppKit (macOS 14.0 Sonoma ou superior)
- **Persistência**: Arquivo JSON criptografado/estruturado em disco local (`Application Support/FinSense/`)
- **Inteligência Artificial**: Integração direta com modelos locais GGUF / MLX via Hugging Face Hub
- **Formatadores**: Padrão monetário brasileiro nativo (BRL `R$ 1.234,56`) com máscaras em tempo real
- **Testes**: XCTest com suíte de testes automatizados cobrindo regras de negócio, amortização e parsing

---

## 💻 Como Rodar Localmente (Desenvolvimento)

### Pré-requisitos
- Mac com processador **Apple Silicon (M1/M2/M3/M4)** ou **Intel**
- **macOS 14.0 (Sonoma)** ou superior instalado
- **Xcode 15+** ou **Command Line Tools** instalados (`xcode-select --install`)

### 1. Clonar o Repositório
```bash
git clone https://github.com/cloviscarmezini/FinSense.git
cd FinSense
```

### 2. Executar os Testes Automatizados
```bash
swift test
```
*Garante que todas as suítes de teste de integração, cálculos e modelos estão íntegras.*

### 3. Compilar e Rodar o App
```bash
swift run
```
O aplicativo abrirá nativamente na sua área de trabalho.

---

## 📦 Como Gerar o Build de Produção (.app)

O projeto inclui um script automatizado que compila a versão otimizada de release, gera o conjunto de ícones em alta resolução (`.icns`), configura o arquivo `Info.plist` e empacota o aplicativo final em **`FinSense.app`**.

### 1. Gerar o Binário de Release e Empacotar
Execute no terminal da raiz do projeto:

```bash
# Compila em modo release otimizado
swift build -c release

# Executa o script de empacotamento
zsh scripts/package_app.sh
```

### 2. Instalar na Máquina
Após a execução do script, o pacote **`FinSense.app`** estará pronto na raiz do projeto. Para instalá-lo:

1. **Via Terminal**:
   ```bash
   cp -R FinSense.app /Applications/
   ```
2. **Ou via Finder**:
   - Abra a pasta do projeto no Finder (`open .`).
   - Arraste o arquivo **`FinSense.app`** para a pasta **Aplicativos** (`/Applications`).

Agora você pode abrir o **FinSense** diretamente pelo **Spotlight** (`Cmd + Espaço`), pelo **Launchpad** ou fixá-lo no seu **Dock** com o ícone oficial do projeto!

---

## 🚀 Como Distribuir para Outros Computadores (DMG / ZIP)

Para compartilhar o aplicativo com outras pessoas ou instalar em outros Macs sem precisar de código-fonte:

### 1. Gerar o Instalador de Distribuição
Execute o script dedicado de distribuição:

```bash
zsh scripts/distribute.sh
```

Este script compila a versão release, assina o app, gera os ícones e cria automaticamente na pasta `dist/`:
- **`dist/FinSense.dmg`**: Imagem de disco padrão do macOS com instalador amigável (arraste para a pasta *Aplicativos*).
- **`dist/FinSense.zip`**: Arquivo comprimido leve e portátil preservando todas as permissões nativas.

### 2. Abrindo em Outro Mac (Gatekeeper do macOS)
Se você distribuir o app sem um certificado pago da Apple Developer Program (usando a assinatura ad-hoc padrão), o macOS exibirá na primeira abertura que o app é de um *desenvolvedor não identificado*. Para abrir normalmente no outro Mac, basta usar qualquer uma das opções:

- **Opção 1 (Mais fácil)**: Clique com o **botão direito** no aplicativo em `/Applications` e selecione **"Abrir"**. Na janela de diálogo que surgir, clique em **"Abrir"**. O macOS lembrará dessa autorização permanentemente.
- **Opção 2**: Vá em **Ajustes do Sistema > Privacidade e Segurança**, role até o fim e clique em **"Abrir Mesmo Assim"**.
- **Opção 3 (Terminal)**: Se baixado via internet/zip, execute no Terminal do Mac de destino:
  ```bash
  xattr -cr /Applications/FinSense.app
  ```

*(Opcional) Se você possuir uma conta de desenvolvedor Apple paga, basta exportar sua identidade antes de rodar o script:*
```bash
export DEVELOPER_ID="Developer ID Application: Seu Nome (XXXXXXXXXX)"
zsh scripts/distribute.sh
```

---

## 🔒 Privacidade e Segurança

- 🚫 **Sem telemetria**: Nenhuma métrica ou dado de uso é enviado para servidores externos.
- 🚫 **Sem dependência de nuvem**: O app funciona perfeitamente sem conexão com a internet.
- 💾 **Seus dados pertencem a você**: O banco de dados fica armazenado em:
  ```text
  ~/Library/Application Support/FinSense/financial_database.json
  ```
  Você pode realizar backups manuais copiando este arquivo a qualquer momento.

---

## 📄 Licença

Distribuído sob a licença proprietária de uso pessoal. Desenvolvido com foco em usabilidade, privacidade e soberania de dados.
