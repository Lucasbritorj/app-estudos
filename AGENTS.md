# App-estudos — execução focada

- Use esta raiz para o app Flutter; não misture a implementação com outras cópias do projeto.
- Patch pontual: `flutter test test/<arquivo>_test.dart`; exemplo existente: `flutter test test/hoje_provider_test.dart`.
- Persistência Hive, backup/importação ou revisões: inclua testes dependentes de integridade, concorrência e rollback aplicáveis.
- Rode `flutter analyze` após alterações Dart; build web quando afetar plataforma, integração web ou entrega.
- Amplie a suíte conforme impacto ou exigência de CI; não repita validação já válida sem mudança, falha ou risco novo.
- Testes Node de API/concursos são separados: localize o teste do módulo alterado; não execute Flutter para mudança exclusivamente Node.
- Preserve invariantes de domínio e alterações existentes; reporte apenas evidências decisivas e pendências.
