# =============================================================================
# Desafio 09 — Crescimento e produção pelo modelo de Clutter (1963)
# Projeto C531 — 9 parcelas permanentes, 43 medições (2,6 a 6,4 anos)
#
# Etapas:
#   1. Pares de medições sucessivas por parcela (I1, B1, I2, B2, V2, S)
#   2. Equação 1 — projeção de área basal (ajuste linear nas variáveis
#      transformadas)
#   3. Equação 2 — volume estático (todas as medições)
#   4. Equação 3 — volume compatível (aplicação sequencial: B2 pela Eq. 1 e,
#      em seguida, V2 pela Eq. 2 avaliada em I2) e validação nas parcelas
#   5. Prognose para S = 20, 22, 24 e 26 m, ICA, IMA e idade de rotação
#      técnica (ICA = IMA)
#
# Como executar (a partir da pasta desafio-09-modelo-clutter/):
#   Rscript desafio09_modelo_clutter.R
# Pacotes: readxl (só se a base do Desafio 08 não estiver disponível), ggplot2
# =============================================================================

suppressPackageStartupMessages(library(ggplot2))

pasta_saida <- "saidas"
dir.create(pasta_saida, showWarnings = FALSE)

sitios        <- c(20, 22, 24, 26)  # classes de sítio da base (m)
passo_idade   <- 1                  # incremento de idade da prognose (anos)
idade_final   <- 9.62               # horizonte da tabela de prognose (anos)
                                    # (idades > máxima observada = extrapolação)

# -----------------------------------------------------------------------------
# 1. Leitura da base (prioridade: base consolidada do Desafio 08)
# -----------------------------------------------------------------------------
ler_base <- function() {
  arq_csv  <- "dados/base_consolidada_sitio.csv"
  arq_xlsx <- "dados/Dados_Clutter_original.xlsx"
  if (file.exists(arq_csv)) {
    d <- read.csv(arq_csv)
    origem <- arq_csv
  } else {
    d <- as.data.frame(readxl::read_excel(arq_xlsx))
    names(d) <- c("projeto", "talhao", "parcela", "id", "b", "hd", "v", "s")
    origem <- arq_xlsx
  }
  d$id_parcela <- paste0("T", d$talhao, "-P", d$parcela)
  d <- d[order(d$talhao, d$parcela, d$id), ]
  cat("Base lida de", origem, ":", nrow(d), "medições,",
      length(unique(d$id_parcela)), "parcelas\n")
  d
}

dados <- ler_base()
idade_max_obs <- max(dados$id)

# -----------------------------------------------------------------------------
# 2. FUNÇÃO: pares de medições sucessivas por parcela
# -----------------------------------------------------------------------------
formar_pares <- function(d) {
  do.call(rbind, lapply(split(d, d$id_parcela), function(x) {
    x <- x[order(x$id), ]
    n <- nrow(x)
    data.frame(id_parcela = x$id_parcela[1], talhao = x$talhao[1],
               parcela = x$parcela[1], s = x$s[1],
               i1 = x$id[-n], i2 = x$id[-1],
               b1 = x$b[-n],  b2 = x$b[-1],
               v1 = x$v[-n],  v2 = x$v[-1])
  }))
}

pares <- formar_pares(dados)
cat("Pares de medições sucessivas:", nrow(pares), "\n\n")

# Métricas de ajuste na escala original da variável
metricas <- function(obs, est, p) {
  res <- obs - est
  n <- length(obs)
  syx <- sqrt(sum(res^2) / (n - p))
  c(n = n, r2 = 1 - sum(res^2) / sum((obs - mean(obs))^2),
    syx = syx, syx_pct = 100 * syx / mean(obs),
    vies_medio = mean(res), rmse = sqrt(mean(res^2)),
    rmse_pct = 100 * sqrt(mean(res^2)) / mean(obs))
}

# -----------------------------------------------------------------------------
# 3. FUNÇÃO: ajuste da Equação 1 — projeção de área basal
#    ln(B2) = (I1/I2) ln(B1) + a0 (1 - I1/I2) + a1 (1 - I1/I2) S
#    Linear nos parâmetros: y = ln(B2) - (I1/I2) ln(B1) = a0 x1 + a1 x2,
#    sem intercepto, com x1 = 1 - I1/I2 e x2 = (1 - I1/I2) S.
#    com_sitio = FALSE ajusta a forma reduzida (sem o termo a1).
# -----------------------------------------------------------------------------
ajustar_eq1 <- function(pares, com_sitio = TRUE) {
  r  <- pares$i1 / pares$i2
  df <- data.frame(y = log(pares$b2) - r * log(pares$b1),
                   x1 = 1 - r, x2 = (1 - r) * pares$s)
  m  <- if (com_sitio) lm(y ~ 0 + x1 + x2, data = df) else lm(y ~ 0 + x1, data = df)
  cf <- coef(m)
  a  <- c(a0 = cf[["x1"]], a1 = if (com_sitio) cf[["x2"]] else 0)
  b2_est <- projetar_b(pares$b1, pares$i1, pares$i2, pares$s, a)
  list(modelo = m, coef = a,
       coef_tabela = summary(m)$coefficients,
       metricas_ln = metricas(log(pares$b2), log(b2_est), length(cf)),
       metricas = metricas(pares$b2, b2_est, length(cf)),
       b2_est = b2_est)
}

# Projeção de B2 pela Equação 1
projetar_b <- function(b1, i1, i2, s, a) {
  r <- i1 / i2
  exp(r * log(b1) + a[["a0"]] * (1 - r) + a[["a1"]] * (1 - r) * s)
}

# -----------------------------------------------------------------------------
# 4. FUNÇÃO: ajuste da Equação 2 — volume estático (todas as medições)
#    ln(V) = b0 + b1 (1/I) + b2 S + b3 ln(B)
# -----------------------------------------------------------------------------
ajustar_eq2 <- function(d) {
  m  <- lm(log(v) ~ I(1 / id) + s + log(b), data = d)
  cf <- coef(m)
  bcoef <- c(b0 = cf[[1]], b1 = cf[[2]], b2 = cf[[3]], b3 = cf[[4]])
  v_est <- estimar_v(d$id, d$s, d$b, bcoef)
  list(modelo = m, coef = bcoef,
       coef_tabela = summary(m)$coefficients,
       metricas_ln = metricas(log(d$v), log(v_est), 4),
       metricas = metricas(d$v, v_est, 4),
       v_est = v_est)
}

# Volume pela Equação 2
estimar_v <- function(i, s, b, bc) {
  exp(bc[["b0"]] + bc[["b1"]] / i + bc[["b2"]] * s + bc[["b3"]] * log(b))
}

# -----------------------------------------------------------------------------
# 5. FUNÇÃO: Equação 3 — volume compatível (projeção de V2)
#    Forma sequencial: B2 = Eq.1(B1, I1, I2, S); V2 = Eq.2(I2, S, B2).
#    Forma analítica equivalente (substituindo a Eq. 1 na Eq. 2 em I2):
#    ln(V2) = b0 + b1/I2 + b2 S + b3 [ (I1/I2) ln(B1) + a0 (1 - I1/I2)
#                                       + a1 (1 - I1/I2) S ]
# -----------------------------------------------------------------------------
projetar_v <- function(b1, i1, i2, s, a, bc) {
  estimar_v(i2, s, projetar_b(b1, i1, i2, s, a), bc)
}

projetar_v_analitica <- function(b1, i1, i2, s, a, bc) {
  r <- i1 / i2
  exp(bc[["b0"]] + bc[["b1"]] / i2 + bc[["b2"]] * s +
      bc[["b3"]] * (r * log(b1) + a[["a0"]] * (1 - r) + a[["a1"]] * (1 - r) * s))
}

# -----------------------------------------------------------------------------
# 6. FUNÇÃO: prognose para um sítio e uma condição inicial (I0, B0)
#    A projeção de Clutter é invariante ao caminho (projetar de I0 direto para
#    I ou em passos sucessivos dá o mesmo resultado), o que é verificado no
#    script. ICA(I) = V(I) - V(I - 1); IMA(I) = V(I) / I.
# -----------------------------------------------------------------------------
simular_prognose <- function(s, i0, b0, idades, a, bc) {
  b <- projetar_b(b0, i0, idades, s, a)
  v <- estimar_v(idades, s, b, bc)
  v_ant <- ifelse(idades - 1 >= i0,
                  estimar_v(idades - 1, s, projetar_b(b0, i0, idades - 1, s, a), bc),
                  NA)
  data.frame(sitio = s, idade = idades,
             area_basal_m2ha = b, volume_m3ha = v,
             ica_m3ha = v - v_ant, ima_m3ha = v / idades)
}

# -----------------------------------------------------------------------------
# 7. FUNÇÃO: idade de rotação técnica (ICA = IMA)
#    Raiz de ICA(I) - IMA(I) em idade contínua, com ICA anual como acima.
# -----------------------------------------------------------------------------
idade_rotacao <- function(s, i0, b0, a, bc, intervalo = c(i0 + 1, 30)) {
  f <- function(i) {
    v  <- estimar_v(i, s, projetar_b(b0, i0, i, s, a), bc)
    va <- estimar_v(i - 1, s, projetar_b(b0, i0, i - 1, s, a), bc)
    (v - va) - v / i
  }
  if (f(intervalo[1]) * f(intervalo[2]) > 0) return(NA_real_)
  uniroot(f, intervalo, tol = 1e-8)$root
}

# =============================================================================
# EXECUÇÃO
# =============================================================================

# --- Equação 1 ---------------------------------------------------------------
eq1 <- ajustar_eq1(pares, com_sitio = TRUE)
cat("Equação 1 (área basal):\n"); print(eq1$coef_tabela)
cat("Métricas na escala de B2:\n"); print(round(eq1$metricas, 4))

eq1_red <- ajustar_eq1(pares, com_sitio = FALSE)   # forma reduzida (sensibilidade)
cat("\nEquação 1 reduzida (sem o termo de sítio):\n"); print(eq1_red$coef_tabela)

# --- Equação 2 ---------------------------------------------------------------
eq2 <- ajustar_eq2(dados)
cat("\nEquação 2 (volume):\n"); print(eq2$coef_tabela)
cat("Métricas na escala de V:\n"); print(round(eq2$metricas, 4))

# --- Equação 3: validação nos pares observados -------------------------------
pares$b2_est <- eq1$b2_est
pares$v2_est <- projetar_v(pares$b1, pares$i1, pares$i2, pares$s, eq1$coef, eq2$coef)
dif_analitica <- max(abs(pares$v2_est -
  projetar_v_analitica(pares$b1, pares$i1, pares$i2, pares$s, eq1$coef, eq2$coef)))
met_eq3 <- metricas(pares$v2, pares$v2_est, 6)
cat("\nEquação 3 (V2 projetado a partir de B1) nos", nrow(pares), "pares:\n")
print(round(met_eq3, 4))
cat("Diferença máxima entre as formas sequencial e analítica:", signif(dif_analitica, 3), "m³/ha\n")

# Desvio médio da projeção de V2 por parcela (%), positivo = superestimativa
pares$desvio_v2_pct <- 100 * (pares$v2_est - pares$v2) / pares$v2
desvio_parcela <- aggregate(desvio_v2_pct ~ id_parcela + s, data = pares, FUN = mean)
cat("\nDesvio médio de V2 projetado por parcela (%):\n")
print(transform(desvio_parcela, desvio_v2_pct = round(desvio_v2_pct, 2)), row.names = FALSE)
write.csv(transform(desvio_parcela, desvio_v2_pct = round(desvio_v2_pct, 2)),
          file.path(pasta_saida, "desvio_eq3_por_parcela.csv"), row.names = FALSE)

# Teste em uma única parcela: projeção a partir da primeira medição
parcela_teste <- "T6-P1"
d_t <- dados[dados$id_parcela == parcela_teste, ]
teste_parcela <- data.frame(
  id_parcela = parcela_teste, idade = d_t$id,
  b_obs = d_t$b, b_proj = projetar_b(d_t$b[1], d_t$id[1], d_t$id, d_t$s[1], eq1$coef),
  v_obs = d_t$v, v_proj = projetar_v(d_t$b[1], d_t$id[1], d_t$id, d_t$s[1], eq1$coef, eq2$coef))
teste_parcela$dif_v_pct <- 100 * (teste_parcela$v_proj - teste_parcela$v_obs) / teste_parcela$v_obs
cat("\nTeste na parcela", parcela_teste, "(projeção a partir da 1ª medição):\n")
print(format(teste_parcela, digits = 4), row.names = FALSE)

# --- Arquivo de equações -----------------------------------------------------
tab_coef <- rbind(
  data.frame(equacao = "Eq1_area_basal", parametro = c("a0", "a1"),
             estimativa = eq1$coef_tabela[, 1], erro_padrao = eq1$coef_tabela[, 2],
             t = eq1$coef_tabela[, 3], p_valor = eq1$coef_tabela[, 4]),
  data.frame(equacao = "Eq2_volume", parametro = c("b0", "b1", "b2", "b3"),
             estimativa = eq2$coef_tabela[, 1], erro_padrao = eq2$coef_tabela[, 2],
             t = eq2$coef_tabela[, 3], p_valor = eq2$coef_tabela[, 4]),
  data.frame(equacao = "Eq1_reduzida_sensibilidade", parametro = "a0",
             estimativa = eq1_red$coef_tabela[, 1], erro_padrao = eq1_red$coef_tabela[, 2],
             t = eq1_red$coef_tabela[, 3], p_valor = eq1_red$coef_tabela[, 4]))
tab_met <- rbind(
  data.frame(equacao = "Eq1_area_basal", escala = "B2 (m2/ha)", t(eq1$metricas)),
  data.frame(equacao = "Eq1_area_basal", escala = "ln(B2)", t(eq1$metricas_ln)),
  data.frame(equacao = "Eq2_volume", escala = "V (m3/ha)", t(eq2$metricas)),
  data.frame(equacao = "Eq2_volume", escala = "ln(V)", t(eq2$metricas_ln)),
  data.frame(equacao = "Eq3_volume_compativel_validacao", escala = "V2 (m3/ha)", t(met_eq3)))
write.csv(transform(tab_coef, estimativa = signif(estimativa, 7), erro_padrao = signif(erro_padrao, 5),
                    t = round(t, 3), p_valor = signif(p_valor, 4)),
          file.path(pasta_saida, "equacoes_clutter.csv"), row.names = FALSE)
write.csv(cbind(tab_met[, 1:2], round(tab_met[, -(1:2)], 4)),
          file.path(pasta_saida, "metricas_ajuste.csv"), row.names = FALSE)
write.csv(transform(pares, b2_est = round(b2_est, 4), v2_est = round(v2_est, 4), desvio_v2_pct = round(desvio_v2_pct, 2)),
          file.path(pasta_saida, "pares_validacao_eq3.csv"), row.names = FALSE)
write.csv(transform(teste_parcela, b_proj = round(b_proj, 4), v_proj = round(v_proj, 4),
                    dif_v_pct = round(dif_v_pct, 2)),
          file.path(pasta_saida, "teste_parcela_T6P1.csv"), row.names = FALSE)

# --- Condição inicial da prognose --------------------------------------------
# Idade inicial: média das idades da 1ª medição das 9 parcelas.
# Área basal inicial: média da área basal na 1ª medição das parcelas de cada sítio.
primeira <- do.call(rbind, lapply(split(dados, dados$id_parcela), function(x) x[which.min(x$id), ]))
i0 <- round(mean(primeira$id), 2)
cond_inicial <- aggregate(b ~ s, data = primeira, FUN = mean)
names(cond_inicial) <- c("sitio", "b0_m2ha")
cond_inicial$n_parcelas <- as.vector(table(primeira$s)[as.character(cond_inicial$sitio)])
cond_inicial$i0_anos <- i0
cat("\nCondição inicial da prognose:\n"); print(cond_inicial, row.names = FALSE)
write.csv(transform(cond_inicial, b0_m2ha = round(b0_m2ha, 4)),
          file.path(pasta_saida, "condicao_inicial.csv"), row.names = FALSE)

# --- Prognose ----------------------------------------------------------------
idades <- seq(i0, idade_final, by = passo_idade)
prog <- do.call(rbind, lapply(seq_len(nrow(cond_inicial)), function(k)
  simular_prognose(cond_inicial$sitio[k], i0, cond_inicial$b0_m2ha[k], idades, eq1$coef, eq2$coef)))
prog$extrapolacao <- prog$idade > idade_max_obs

# Verificação de invariância ao caminho (passo a passo = direto)
k <- 1
b_passo <- cond_inicial$b0_m2ha[k]
for (j in 2:length(idades)) b_passo <- projetar_b(b_passo, idades[j - 1], idades[j], cond_inicial$sitio[k], eq1$coef)
cat("\nInvariância ao caminho (S =", cond_inicial$sitio[k], "): B direto =",
    round(prog$area_basal_m2ha[prog$sitio == cond_inicial$sitio[k]][length(idades)], 6),
    "; B passo a passo =", round(b_passo, 6), "\n")

prog_out <- prog
prog_out[, 3:6] <- round(prog_out[, 3:6], 3)
write.csv(prog_out, file.path(pasta_saida, "prognose_producao.csv"), row.names = FALSE)

# Diferença de produção entre o sítio mais e o menos produtivo ao longo da idade
larg <- reshape(prog[, c("sitio", "idade", "volume_m3ha")], idvar = "idade",
                timevar = "sitio", direction = "wide")
dif_sitios <- data.frame(idade = larg$idade,
                         v_s20 = larg$volume_m3ha.20, v_s26 = larg$volume_m3ha.26,
                         diferenca_abs_m3ha = larg$volume_m3ha.26 - larg$volume_m3ha.20,
                         razao_s26_s20 = larg$volume_m3ha.26 / larg$volume_m3ha.20)
cat("\nDiferença de volume entre S = 26 e S = 20:\n"); print(round(dif_sitios, 2), row.names = FALSE)
write.csv(round(dif_sitios, 3), file.path(pasta_saida, "diferenca_entre_sitios.csv"), row.names = FALSE)

# --- Idade de rotação técnica ------------------------------------------------
rot <- do.call(rbind, lapply(seq_len(nrow(cond_inicial)), function(k) {
  s <- cond_inicial$sitio[k]; b0 <- cond_inicial$b0_m2ha[k]
  ir  <- idade_rotacao(s, i0, b0, eq1$coef, eq2$coef)
  ir2 <- idade_rotacao(s, i0, b0, eq1_red$coef, eq2$coef)
  v_r <- estimar_v(ir, s, projetar_b(b0, i0, ir, s, eq1$coef), eq2$coef)
  data.frame(sitio = s, idade_rotacao_anos = ir,
             volume_na_rotacao_m3ha = v_r, ima_na_rotacao_m3ha = v_r / ir,
             extrapolacao = ir > idade_max_obs,
             idade_rotacao_eq1_reduzida = ir2)
}))
cat("\nIdade de rotação técnica (ICA = IMA):\n"); print(format(rot, digits = 4), row.names = FALSE)
write.csv(transform(rot, idade_rotacao_anos = round(idade_rotacao_anos, 2),
                    volume_na_rotacao_m3ha = round(volume_na_rotacao_m3ha, 2),
                    ima_na_rotacao_m3ha = round(ima_na_rotacao_m3ha, 2),
                    idade_rotacao_eq1_reduzida = round(idade_rotacao_eq1_reduzida, 2)),
          file.path(pasta_saida, "idade_rotacao_tecnica.csv"), row.names = FALSE)

# =============================================================================
# GRÁFICOS
# =============================================================================
tema <- theme_bw(base_size = 11) + theme(legend.position = "bottom")
dados$S <- factor(dados$s)

# Curvas contínuas para os gráficos
grade <- seq(i0, idade_final, by = 0.02)
curvas <- do.call(rbind, lapply(seq_len(nrow(cond_inicial)), function(k)
  simular_prognose(cond_inicial$sitio[k], i0, cond_inicial$b0_m2ha[k], grade, eq1$coef, eq2$coef)))
curvas$S <- factor(curvas$sitio); prog$S <- factor(prog$sitio)

# Curva de produção
g_prod <- ggplot() +
  annotate("rect", xmin = idade_max_obs, xmax = idade_final, ymin = -Inf, ymax = Inf,
           fill = "grey90") +
  annotate("text", x = (idade_max_obs + idade_final) / 2, y = 15,
           label = "extrapolação\n(além da idade máxima observada)", size = 3, colour = "grey30") +
  geom_point(data = dados, aes(id, v, colour = S), alpha = 0.45, size = 1.6) +
  geom_line(data = curvas, aes(idade, volume_m3ha, colour = S, linetype = S), linewidth = 0.9) +
  geom_point(data = prog, aes(idade, volume_m3ha, colour = S, shape = S), size = 2) +
  labs(x = "Idade (anos)", y = expression("Volume (m"^3*" ha"^-1*")"),
       colour = "Sítio (m)", linetype = "Sítio (m)", shape = "Sítio (m)",
       title = "Curvas de produção em volume — modelo de Clutter",
       subtitle = "Linhas: prognose; pontos claros: volumes observados nas parcelas") +
  tema
ggsave(file.path(pasta_saida, "grafico_curva_producao.png"), g_prod, width = 7.5, height = 5.5, dpi = 300)

# ICA e IMA por sítio
inc <- rbind(data.frame(sitio = curvas$sitio, idade = curvas$idade, valor = curvas$ica_m3ha, curva = "ICA"),
             data.frame(sitio = curvas$sitio, idade = curvas$idade, valor = curvas$ima_m3ha, curva = "IMA"))
inc <- inc[!is.na(inc$valor), ]
inc$painel <- factor(paste("S =", inc$sitio, "m"), levels = paste("S =", sitios, "m"))
rot$painel <- factor(paste("S =", rot$sitio, "m"), levels = paste("S =", sitios, "m"))
pts <- rbind(data.frame(sitio = prog$sitio, idade = prog$idade, valor = prog$ica_m3ha, curva = "ICA"),
             data.frame(sitio = prog$sitio, idade = prog$idade, valor = prog$ima_m3ha, curva = "IMA"))
pts <- pts[!is.na(pts$valor), ]
pts$painel <- factor(paste("S =", pts$sitio, "m"), levels = paste("S =", sitios, "m"))

g_inc <- ggplot(inc, aes(idade, valor, linetype = curva)) +
  annotate("rect", xmin = idade_max_obs, xmax = idade_final, ymin = -Inf, ymax = Inf, fill = "grey92") +
  geom_line(linewidth = 0.8) +
  geom_point(data = pts, aes(shape = curva), size = 1.8) +
  geom_vline(data = rot, aes(xintercept = idade_rotacao_anos), colour = "red", linetype = "dashed") +
  geom_text(data = rot, aes(x = idade_rotacao_anos, y = Inf,
                            label = paste0("ICA = IMA\n", sub(".", ",", sprintf("%.1f", idade_rotacao_anos), fixed = TRUE), " anos")),
            vjust = 1.3, hjust = -0.05, size = 3, colour = "red", inherit.aes = FALSE) +
  facet_wrap(~ painel, ncol = 2) +
  labs(x = "Idade (anos)", y = expression("Incremento (m"^3*" ha"^-1*" ano"^-1*")"),
       linetype = NULL, shape = NULL,
       title = "Incremento corrente anual (ICA) e incremento médio anual (IMA)",
       subtitle = "Linha vermelha: idade de rotação técnica; área cinza: extrapolação") +
  tema
ggsave(file.path(pasta_saida, "grafico_ica_ima.png"), g_inc, width = 8, height = 6.5, dpi = 300)

# Resíduos e validação
res_df <- rbind(
  data.frame(painel = "Eq. 1 — área basal (B2)", estimado = pares$b2_est,
             residuo_pct = 100 * (pares$b2 - pares$b2_est) / pares$b2),
  data.frame(painel = "Eq. 2 — volume (V)", estimado = eq2$v_est,
             residuo_pct = 100 * (dados$v - eq2$v_est) / dados$v),
  data.frame(painel = "Eq. 3 — volume compatível (V2)", estimado = pares$v2_est,
             residuo_pct = 100 * (pares$v2 - pares$v2_est) / pares$v2))
res_df$painel <- factor(res_df$painel, levels = unique(res_df$painel))
g_res <- ggplot(res_df, aes(estimado, residuo_pct)) +
  geom_hline(yintercept = 0, colour = "grey40") +
  geom_point(size = 1.8, alpha = 0.8) +
  facet_wrap(~ painel, scales = "free_x", ncol = 3) +
  labs(x = "Valor estimado", y = "Resíduo (%)", title = "Distribuição dos resíduos") +
  theme_bw(base_size = 10)
ggsave(file.path(pasta_saida, "grafico_residuos.png"), g_res, width = 9, height = 3.6, dpi = 300)

g_val <- ggplot(pares, aes(v2_est, v2)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey40") +
  geom_point(aes(colour = factor(s)), size = 2) +
  labs(x = expression("V2 projetado pela Eq. 3 (m"^3*" ha"^-1*")"),
       y = expression("V2 observado (m"^3*" ha"^-1*")"), colour = "Sítio (m)",
       title = "Validação da equação de volume compatível") +
  coord_equal() + tema
ggsave(file.path(pasta_saida, "grafico_validacao_eq3.png"), g_val, width = 5.5, height = 5.8, dpi = 300)

cat("\nArquivos gravados em", pasta_saida, ":\n"); print(list.files(pasta_saida))
