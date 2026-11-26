# Desafio 09 — Crescimento e produção pelo modelo de Clutter

Projeto C531, com 9 parcelas permanentes e 43 medições feitas entre 2,6 e 6,4 anos. Este desafio ajusta o sistema de Clutter (1963), gera a prognose de área basal e volume para os sítios S = 20, 22, 24 e 26 m e identifica a idade de rotação técnica (ICA = IMA) de cada sítio.

## Estrutura da pasta

```
desafio-09-modelo-clutter/
├── README.md
├── relatorio.md
├── desafio09_modelo_clutter.R
├── dados/
│   ├── base_consolidada_sitio.csv     # saída do Desafio 08 (entrada principal)
│   └── Dados_Clutter_original.xlsx    # usada só se o CSV não existir
└── saidas/
    ├── equacoes_clutter.csv           # coeficientes das Eq. 1 e 2   (exigido)
    ├── metricas_ajuste.csv            # R², Syx, Syx%, viés, RMSE    (exigido)
    ├── prognose_producao.csv          # sitio, idade, area_basal_m2ha, volume_m3ha, ica_m3ha, ima_m3ha  (exigido)
    ├── grafico_curva_producao.png     # (exigido)
    ├── grafico_ica_ima.png            # (exigido)
    ├── idade_rotacao_tecnica.csv
    ├── condicao_inicial.csv
    ├── diferenca_entre_sitios.csv
    ├── pares_validacao_eq3.csv
    ├── teste_parcela_T6P1.csv
    ├── desvio_eq3_por_parcela.csv
    ├── grafico_residuos.png
    ├── grafico_validacao_eq3.png
    └── log_execucao.txt
```

## Como executar

Na pasta `desafio-09-modelo-clutter/`:

```bash
Rscript desafio09_modelo_clutter.R
```

O script usa os pacotes `ggplot2` e `readxl` (este último só se o CSV do Desafio 08 não estiver na pasta `dados/`) e foi testado no R 4.3.3.

## Equações

| Equação | Forma | Dados do ajuste |
|---|---|---|
| 1 — projeção de área basal | ln(B2) = (I1/I2)·ln(B1) + a0·(1 − I1/I2) + a1·(1 − I1/I2)·S | 34 pares de medições sucessivas; regressão linear sem intercepto em y = ln(B2) − (I1/I2)·ln(B1) |
| 2 — volume estático | ln(V) = b0 + b1·(1/I) + b2·S + b3·ln(B) | 43 medições |
| 3 — volume compatível | B2 pela Eq. 1 e, em seguida, V2 pela Eq. 2 avaliada em I2 (forma **sequencial**) | — |

O script também calcula a forma analítica da Eq. 3 (a Eq. 1 substituída na Eq. 2) e confirma que dá o mesmo resultado da forma sequencial.

## Condição inicial e incremento de idade da prognose

- **Idade inicial (I0): 2,62 anos**, a média das idades da primeira medição das 9 parcelas, comum aos quatro sítios.
- **Área basal inicial (B0):** a média da área basal na primeira medição das parcelas de cada sítio.

| Sítio (m) | B0 (m²/ha) | Parcelas |
|---|---|---|
| 20 | 6,49 | 2 |
| 22 | 6,85 | 3 |
| 24 | 8,93 | 3 |
| 26 | 9,78 | 1 |

- **Incremento de idade: 1 ano** (2,62; 3,62; …; 9,62).
- **ICA(I) = V(I) − V(I − 1)** e **IMA(I) = V(I)/I**.
- A **idade de rotação técnica** é obtida numericamente (`uniroot`) como a idade contínua em que ICA = IMA.

**Horizonte.** A maior idade observada é 6,37 anos. A tabela foi estendida até 9,62 anos para mostrar o comportamento das curvas depois do cruzamento de ICA e IMA. As linhas com `extrapolacao = TRUE` em `prognose_producao.csv` estão fora da amplitude dos dados e devem ser lidas com cautela. As quatro idades de rotação técnica ficaram **dentro** da amplitude observada.
