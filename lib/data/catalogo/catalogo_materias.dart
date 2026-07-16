/// Catálogo de matérias recorrentes em concursos públicos, com siglas
/// canônicas usadas como tag (#DC, #AFO...). É a fonte do seed das páginas
/// de resumo — de propósito NÃO vira matéria de estudo: dashboard, fila e
/// planejamento só enxergam o que o usuário cadastrar.
class MateriaCatalogo {
  final String sigla;
  final String nome;

  const MateriaCatalogo(this.sigla, this.nome);
}

const catalogoMaterias = <MateriaCatalogo>[
  MateriaCatalogo('LP', 'Língua Portuguesa'),
  MateriaCatalogo('RLM', 'Raciocínio Lógico-Matemático'),
  MateriaCatalogo('MAT', 'Matemática'),
  MateriaCatalogo('INF', 'Informática'),
  MateriaCatalogo('DC', 'Direito Constitucional'),
  MateriaCatalogo('DA', 'Direito Administrativo'),
  MateriaCatalogo('DCV', 'Direito Civil'),
  MateriaCatalogo('DP', 'Direito Penal'),
  MateriaCatalogo('DPC', 'Direito Processual Civil'),
  MateriaCatalogo('DPP', 'Direito Processual Penal'),
  MateriaCatalogo('DT', 'Direito do Trabalho'),
  MateriaCatalogo('DPT', 'Direito Processual do Trabalho'),
  MateriaCatalogo('DTR', 'Direito Tributário'),
  MateriaCatalogo('DPV', 'Direito Previdenciário'),
  MateriaCatalogo('DEM', 'Direito Empresarial'),
  MateriaCatalogo('DF', 'Direito Financeiro'),
  MateriaCatalogo('DH', 'Direitos Humanos'),
  MateriaCatalogo('LPE', 'Legislação Penal Especial'),
  MateriaCatalogo('AFO', 'Administração Financeira e Orçamentária'),
  MateriaCatalogo('ADM', 'Administração Geral'),
  MateriaCatalogo('APB', 'Administração Pública'),
  MateriaCatalogo('CTB', 'Contabilidade Geral'),
  MateriaCatalogo('CTP', 'Contabilidade Pública'),
  MateriaCatalogo('AUD', 'Auditoria'),
  MateriaCatalogo('CE', 'Controle Externo'),
  MateriaCatalogo('ECO', 'Economia'),
  MateriaCatalogo('EST', 'Estatística'),
  MateriaCatalogo('AD', 'Análise de Dados'),
  MateriaCatalogo('TI', 'Tecnologia da Informação'),
  MateriaCatalogo('SI', 'Segurança da Informação'),
  MateriaCatalogo('ETI', 'Ética no Serviço Público'),
  MateriaCatalogo('RED', 'Redação'),
  MateriaCatalogo('ING', 'Inglês'),
  MateriaCatalogo('ATU', 'Atualidades'),
  MateriaCatalogo('GP', 'Gestão de Pessoas'),
  MateriaCatalogo('LEG', 'Legislação Específica'),
];

const _palavrasVazias = {
  'de', 'do', 'da', 'dos', 'das', 'e', 'em', 'no', 'na', 'nos', 'nas',
  'para', 'ao', 'à', 'a', 'o',
};

/// Sigla derivada para matéria FORA do catálogo: iniciais das palavras
/// significativas ("Direito do Trabalho" -> DT); nome de uma palavra vira
/// as 3 primeiras letras ("Matemática" -> MAT). Sempre maiúscula.
String siglaPara(String nome) {
  final palavras = nome
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && !_palavrasVazias.contains(p.toLowerCase()))
      .toList();
  if (palavras.isEmpty) return '?';
  if (palavras.length == 1) {
    final p = palavras.first;
    return p.substring(0, p.length < 3 ? p.length : 3).toUpperCase();
  }
  return palavras.map((p) => p[0]).join().toUpperCase();
}
