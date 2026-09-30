#!/usr/bin/env bash
# bem doctor — checagem de saúde da arquitetura BEM (genérico, auto-descoberto)
# Uso: ./bem-doctor.sh
# Config por env (opcional):
#   BEM_ROOT     raiz onde ficam os territórios/empresas (default: $HOME/Projetos)
#   BEM_MIRRORS  espelhos do próprio repo BEM, separados por ':' (ex: "/a/BEM:/b/BEM")
set -uo pipefail

OK=0; FAIL=0
ok()   { echo "  ✅ $1"; OK=$((OK+1)); }
falha(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# raiz dos territórios (configurável; nada hardcoded)
BEM_ROOT="${BEM_ROOT:-$HOME/Projetos}"
# repo BEM = onde este script mora
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🩺 BEM doctor"
echo "   raiz de territórios: $BEM_ROOT"
echo

echo "— Espelhos do repo BEM —"
# o próprio repo + quaisquer espelhos declarados em BEM_MIRRORS
MIRRORS="$SELF_DIR"
[ -n "${BEM_MIRRORS:-}" ] && MIRRORS="$MIRRORS:$BEM_MIRRORS"
IFS=':' read -ra DIRS <<< "$MIRRORS"
for DIR in "${DIRS[@]}"; do
  [ -z "$DIR" ] && continue
  if [ -d "$DIR/.git" ]; then
    LOCAL=$(git -C "$DIR" rev-parse main 2>/dev/null)
    REMOTO=$(git -C "$DIR" rev-parse origin/main 2>/dev/null)
    if [ "$LOCAL" = "$REMOTO" ]; then ok "$DIR em sync com origin/main (${LOCAL:0:7})"
    else falha "$DIR divergente: local ${LOCAL:0:7} vs origin ${REMOTO:0:7} — rode git pull/push"; fi
    SUJO=$(git -C "$DIR" status --porcelain | wc -l)
    [ "$SUJO" -eq 0 ] && ok "$DIR working tree limpo" || falha "$DIR tem $SUJO arquivo(s) não commitado(s)"
  else
    falha "sem .git em $DIR"
  fi
done

if [ ! -d "$BEM_ROOT" ]; then
  echo
  echo "ℹ️  BEM_ROOT não existe ($BEM_ROOT). Defina BEM_ROOT e rode de novo."
  echo
  [ "$FAIL" -eq 0 ] && echo "🟢 $OK ok" || echo "🔴 $FAIL problema(s), $OK ok"
  exit "$FAIL"
fi

echo
echo "— Elos (presença, nunca conteúdo) —"
# descobre todo .<ticker>.elo.env até 2 níveis abaixo da raiz.
# Sem mapfile: ele é do bash 4+, e o macOS ainda traz o bash 3.2. Sob `set -u`,
# a ausência dele deixava ELOS indefinido e o doctor pulava em silêncio as duas
# últimas seções, terminando em "🟢 Tudo são" sem ter olhado nada.
ELOS=(); N_ELOS=0
while IFS= read -r _LINHA; do
  [ -z "$_LINHA" ] && continue
  ELOS[$N_ELOS]="$_LINHA"; N_ELOS=$((N_ELOS+1))
done < <(find "$BEM_ROOT" -maxdepth 3 -type f -name '.*.elo.env' 2>/dev/null | sort)
if [ "$N_ELOS" -eq 0 ]; then
  falha "nenhum elo (.<ticker>.elo.env) encontrado sob $BEM_ROOT"
else
  for ELO in "${ELOS[@]}"; do ok "elo presente: ${ELO#$BEM_ROOT/}"; done
fi

echo
echo "— Elo fora de git (proteção) —"
# para cada território que é repo git, confirma que o próprio elo está ignorado
[ "$N_ELOS" -gt 0 ] && for ELO in "${ELOS[@]}"; do
  DIR="$(dirname "$ELO")"
  if [ -d "$DIR/.git" ]; then
    git -C "$DIR" check-ignore -q "$(basename "$ELO")" 2>/dev/null \
      && ok "$(basename "$DIR"): elo ignorado pelo git" \
      || falha "$(basename "$DIR"): repo SEM proteção de elo no .gitignore"
  fi
done

echo
echo "— Kit BEM nos territórios —"
# territórios = diretórios que contêm um elo
[ "$N_ELOS" -gt 0 ] && for ELO in "${ELOS[@]}"; do
  PROJ="$(dirname "$ELO")"
  FALTAM=""
  for F in AGENTS.md CLAUDE.md BRIEFING.md TASKS.md CHATS.md; do
    [ -f "$PROJ/$F" ] || FALTAM="$FALTAM $F"
  done
  [ -z "$FALTAM" ] && ok "$(basename "$PROJ"): kit completo" || falha "$(basename "$PROJ"): falta$FALTAM"
done

echo
[ "$FAIL" -eq 0 ] && echo "🟢 Tudo são — $OK checagens ok" || echo "🔴 $FAIL problema(s), $OK ok"
exit "$FAIL"
