# Instruções para contribuir

## Nunca mexer direto na `main`

- Não faça commit, merge nem push direto na `main`.
- Todo trabalho começa numa branch nova, criada a partir da `main` atualizada:

  ```
  git checkout main
  git pull
  git checkout -b <tipo>/<assunto>
  ```

  Exemplos de nome: `feature/tarefas-energia`, `correcao/porta-abrigo`, `arte/estufa-v4`.
- Faça os commits nessa branch e envie com `git push -u origin <branch>`.
- Para levar o trabalho à `main`, abra um Pull Request no GitHub. O merge só acontece pelo PR, depois que o jogo
  abrir e rodar sem erros na branch.
- Se a `main` andou enquanto você trabalhava, traga as mudanças dela para a sua branch (`git merge main`) e resolva os
  conflitos lá, nunca na `main`.
