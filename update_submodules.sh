#!/usr/bin/env bash
#
# update_submodules.sh
#
# Đồng bộ (pin) từng submodule về đúng branch + commit hash khai báo trong
# file config dùng chung (submodules.conf), sau đó tuỳ chọn commit lại con
# trỏ SHA ở repo cha.
#
# Cách dùng:
#   chmod +x update_submodules.sh
#   ./update_submodules.sh                # dùng submodules.conf trong thư mục hiện tại
#   ./update_submodules.sh -f other.conf  # dùng file config khác
#
# An toàn để chạy lại nhiều lần (idempotent):
#   - Nếu submodule đã đúng commit -> chỉ báo OK, không làm gì thêm
#   - Nếu commit trong config để trống -> chỉ pull mới nhất theo branch
#   - Nếu đổi commit hash trong config (upstream có bản mới) -> chạy lại là
#     tự pin sang commit mới

set -u

CONF_FILE="submodules.conf"
[ "${1:-}" = "-f" ] && CONF_FILE="$2"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

if [ ! -d ".git" ]; then
  echo -e "${RED}[LỖI]${NC} Thư mục hiện tại không phải gốc git repo (repo cha)."
  exit 1
fi

if [ ! -f "$CONF_FILE" ]; then
  echo -e "${RED}[LỖI]${NC} Không tìm thấy file config '$CONF_FILE'."
  exit 1
fi

REPO_ROOT="$(pwd)"
BASE_URL=""
FAILED=()
PINNED=()
UPDATED_BRANCH_ONLY=()

echo -e "${BLUE}== Bắt đầu đồng bộ submodule từ '$CONF_FILE' ==${NC}"
echo ""

LINE_NO=0
while IFS='|' read -r c1 c2 c3 c4; do
  LINE_NO=$((LINE_NO + 1))

  [[ -z "${c1:-}" || "$c1" =~ ^[[:space:]]*# ]] && continue

  if [[ "$c1" =~ ^BASE_URL= ]]; then
    BASE_URL="${c1#BASE_URL=}"
    continue
  fi

  repo="$c1"; branch="$c2"; path="$c3"; expected="${c4:-}"

  # Dòng không có branch/path (vd "demo", "host") -> bỏ qua có chủ đích
  if [ -z "${branch:-}" ] || [ -z "${path:-}" ]; then
    echo -e "${YELLOW}-- Bỏ qua '$repo' (chưa khai báo branch/path trong config) --${NC}"
    continue
  fi

  if [ ! -d "$REPO_ROOT/$path" ]; then
    echo -e "${RED}!! Không tìm thấy thư mục '$path'${NC} — chạy add_submodules.sh trước đã."
    FAILED+=("$path: chưa được add")
    continue
  fi

  echo -e "${BLUE}== $path (branch: $branch) ==${NC}"
  cd "$REPO_ROOT/$path" || { FAILED+=("$path: không cd được"); continue; }

  git fetch origin >/dev/null 2>&1

  if [ -n "$expected" ]; then
    # ---- PIN chính xác vào commit hash ----
    if ! git cat-file -e "${expected}^{commit}" 2>/dev/null; then
      git fetch origin "$branch" >/dev/null 2>&1
    fi

    if git cat-file -e "${expected}^{commit}" 2>/dev/null; then
      current=$(git rev-parse HEAD)
      target=$(git rev-parse "$expected")
      if [ "$current" = "$target" ]; then
        echo -e "  ${GREEN}OK${NC}: đã ở đúng commit ${expected:0:7}, không cần đổi."
      else
        git checkout --detach "$expected" >/dev/null 2>&1
        echo -e "  ${GREEN}PINNED${NC}: HEAD -> ${expected:0:7} (detached)"
        PINNED+=("$path -> ${expected:0:7}")
      fi
    else
      echo -e "  ${RED}[LỖI]${NC} Không tìm thấy commit '$expected' trên remote lẫn local."
      FAILED+=("$path: không tìm thấy commit $expected")
    fi
  else
    # ---- Không pin commit cụ thể, chỉ theo branch mới nhất ----
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      git checkout "$branch" >/dev/null 2>&1
    else
      git checkout -b "$branch" "origin/$branch" >/dev/null 2>&1
    fi
    git pull origin "$branch" >/dev/null 2>&1
    actual=$(git rev-parse --short HEAD)
    echo -e "  ${GREEN}OK${NC}: HEAD = $actual (theo branch mới nhất, không pin commit cụ thể)"
    UPDATED_BRANCH_ONLY+=("$path @ $actual")
  fi

  cd "$REPO_ROOT" || exit 1
  echo ""
done < "$CONF_FILE"

# --------------------------------------------------------------------------
# TỔNG KẾT
# --------------------------------------------------------------------------
echo -e "${BLUE}== Tổng kết ==${NC}"
if [ "${#PINNED[@]}" -gt 0 ]; then
  echo -e "${GREEN}Đã pin sang commit mới:${NC}"
  printf '  - %s\n' "${PINNED[@]}"
fi
if [ "${#UPDATED_BRANCH_ONLY[@]}" -gt 0 ]; then
  echo -e "${YELLOW}Chỉ pull theo branch (không pin commit cụ thể):${NC}"
  printf '  - %s\n' "${UPDATED_BRANCH_ONLY[@]}"
fi
if [ "${#FAILED[@]}" -gt 0 ]; then
  echo -e "${RED}Lỗi:${NC}"
  printf '  - %s\n' "${FAILED[@]}"
fi

echo ""
echo -e "${BLUE}== git status ở repo cha ==${NC}"
git status --short

if [ "${#PINNED[@]}" -gt 0 ] || [ "${#UPDATED_BRANCH_ONLY[@]}" -gt 0 ]; then
  echo ""
  read -p "Commit lại con trỏ submodule ở repo cha? (y/N) " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    git add -A
    git commit -m "chore: sync submodules per submodules.conf"
    echo -e "${GREEN}Đã commit.${NC} Nhớ: git push origin <branch-repo-cha>"
  else
    echo "Bỏ qua commit — tự chạy 'git add -A && git commit' khi sẵn sàng."
  fi
fi