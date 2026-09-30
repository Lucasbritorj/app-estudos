# Coleta de concursos

`node --test tool/concursos/coletor.test.cjs` valida fixtures oficiais e limites.
`node tool/concursos/live.cjs` consulta fontes reais, sem credenciais.

Fixtures capturadas das páginas oficiais em 07/09/2026. Cebraspe usa endpoint JSON público identificado no JavaScript do próprio site. FGV usa links HTML oficiais. A Cesgranrio foi removida em 30/09/2026: responde HTTP 403 à coleta a partir da Vercel. Acompanhamentos antigos dela seguem válidos no estado e no backup, mas não são consultados. Não há parser de salário/escolaridade/localização inventado: apenas salário disponível no JSON Cebraspe é estruturado. Os demais campos permanecem desconhecidos.

Function GET `/api/concursos?fonte=fgv|cebraspe&concurso=slug` (concurso opcional). Domínios exatos e HTTPS permitidos, sem URL arbitrária, credenciais, cron, banco ou dependências Node. Redirecionamentos também são validados; 8 segundos por fase e 2 MB por resposta. No detalhe, SHA-256 verifica até 12 documentos simultâneos. Excedentes/falhas ficam explicitamente não verificados. Não faz OCR nem interpreta alterações de conteúdo. Cache CDN de cinco horas + uma hora de stale; cliente TTL seis horas e intervalo manual mínimo de cinco minutos. O timeout cliente é 25 segundos.

`ConcursosScreen` é a entrada Flutter. Estado local atômico em `HiveBoxes.config['concursos']`: perfil, acompanhados, consultas, publicacoes, aprovadas. `ConcursosStore.atualizar()` permite acionar ao abrir/retomar o app; a tela também atualiza ao abrir/retomar e a cada cinco minutos enquanto visível. A caixa observável reflete importação/restauração.

Marca de conferência reconhece apenas a versão lida; alterações de edital são feitas pelo usuário no editor/importador existente acessível pelo diálogo. Links e metadados mudados geram versão anterior; SHA-256 detecta documento substituído na mesma URL. A comparação binária exige leitura humana do documento para conhecer diferenças semânticas.

Catálogos não são uma lista exaustiva de inscrições abertas: FGV inclui concursos em andamento e apenas os links da página consultada; o texto da tela avisa essa limitação. Os filtros de cargo/área operam no título, remuneração somente quando publicada; escolaridade e localização ficam registradas como preferências para conferência humana no edital.
