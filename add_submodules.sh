#!/usr/bin/env bash
#
# add_submodules.sh
#
# Add hàng loạt submodule vào repo cha, dựa trên file config dùng chung
# (submodules.conf) có khai báo BASE_URL để dễ tái sử dụng.
#
# Cách dùng:
#   chmod +x add_submodules.sh
#   ./add_submodules.sh                  # dùng submodules.conf trong thư mục hiện tại
#   ./add_submodules.sh -f other.conf     # dùng file config khác
#
# Khi cần add thêm repo mới sau này: chỉ thêm dòng mới vào cuối submodules.conf
# rồi chạy lại script — các dòng đã add trước đó sẽ tự động bị bỏ qua (SKIP).
#
# Khi đổi username/org GitHub: chỉ sửa dòng "BASE_URL=..." ở đầu file config,
# không cần sửa từng dòng repo.

set -u

CONF_FILE="submodules.conf"
[ "${1:-}" = "-f" ] && CONF_FILE="$2"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

TOTAL=0; OK=0; SKIPPED=0; FAILED=0
FAILED_LIST=()
BASE_URL=""

# --------------------------------------------------------------------------
# KIỂM TRA 0: đang đứng đúng chỗ chưa (gốc repo cha)
# --------------------------------------------------------------------------
if [ ! -d ".git" ]; then
  echo -e "${RED}[LỖI]${NC} Thư mục hiện tại không phải gốc git repo."
  echo "       Hãy cd vào repo cha rồi chạy lại."
  exit 1
fi

if [ ! -f "$CONF_FILE" ]; then
  echo -e "${RED}[LỖI]${NC} Không tìm thấy file config '$CONF_FILE'."
  exit 1
fi

# --------------------------------------------------------------------------
# Hàm: resolve repo ngắn gọn -> URL đầy đủ, dựa vào BASE_URL
# --------------------------------------------------------------------------
resolve_url() {
  local repo="$1"
  if [[ "$repo" =~ ^https?:// || "$repo" =~ ^git@ ]]; then
    # Đã là URL đầy đủ -> dùng nguyên
    echo "$repo"
    return
  fi
  if [ -z "$BASE_URL" ]; then
    echo ""  # không resolve được, để hàm gọi tự báo lỗi
    return
  fi
  local base="${BASE_URL%/}"
  local name="$repo"
  [[ "$name" != *.git ]] && name="${name}.git"
  echo "${base}/${name}"
}

echo -e "${BLUE}== Bắt đầu add submodule từ '$CONF_FILE' ==${NC}"
echo ""

LINE_NO=0
while IFS='|' read -r c1 c2 c3 c4; do
  LINE_NO=$((LINE_NO + 1))

  # Bỏ dòng trống hoặc comment
  [[ -z "${c1:-}" || "$c1" =~ ^[[:space:]]*# ]] && continue

  # Dòng khai báo BASE_URL
  if [[ "$c1" =~ ^BASE_URL= ]]; then
    BASE_URL="${c1#BASE_URL=}"
    echo -e "${BLUE}[CONFIG]${NC} BASE_URL = $BASE_URL"
    echo ""
    continue
  fi

  repo="$c1"; branch="$c2"; path="$c3"
  # c4 (commit hash) không dùng trong script add, chỉ update_submodules.sh dùng

  TOTAL=$((TOTAL + 1))
  echo -e "${BLUE}--- Dòng $LINE_NO ---${NC}"

  # ------------------------------------------------------------------------
  # KIỂM TRA 1: dòng config có đủ cột không
  # ------------------------------------------------------------------------
  if [ -z "${repo:-}" ] || [ -z "${branch:-}" ] || [ -z "${path:-}" ]; then
    echo -e "  ${YELLOW}[SKIP]${NC} Dòng thiếu branch/path (có thể cố ý để trống, vd 'demo', 'host')."
    SKIPPED=$((SKIPPED + 1))
    echo ""
    continue
  fi

  url=$(resolve_url "$repo")
  if [ -z "$url" ]; then
    echo -e "  ${RED}[LỖI CONFIG]${NC} Không resolve được URL cho '$repo' — thiếu BASE_URL và repo không phải URL đầy đủ."
    FAILED=$((FAILED + 1)); FAILED_LIST+=("$path: thiếu BASE_URL")
    echo ""
    continue
  fi

  echo "  repo   : $url"
  echo "  branch : $branch"
  echo "  path   : $path"

  # ------------------------------------------------------------------------
  # KIỂM TRA 2: path đã tồn tại (và có nội dung) chưa
  # ------------------------------------------------------------------------
  if [ -e "$path" ] && [ "$(ls -A "$path" 2>/dev/null)" ]; then
    echo -e "  ${YELLOW}[SKIP]${NC} '$path' đã tồn tại và không rỗng — có thể đã add trước đó."
    SKIPPED=$((SKIPPED + 1))
    echo ""
    continue
  fi

  # ------------------------------------------------------------------------
  # KIỂM TRA 3: repo/branch có thật sự tồn tại trên remote không
  # ------------------------------------------------------------------------
  echo -n "  Kiểm tra remote... "
  remote_sha=$(git ls-remote "$url" "refs/heads/$branch" 2>&1)
  if [ $? -ne 0 ]; then
    echo -e "${RED}THẤT BẠI${NC}"
    echo -e "  ${RED}[LỖI]${NC} Không truy cập được repo hoặc URL sai:"
    echo "$remote_sha" | sed 's/^/         /'
    FAILED=$((FAILED + 1)); FAILED_LIST+=("$path: không truy cập được repo")
    echo ""
    continue
  fi
  if [ -z "$remote_sha" ]; then
    echo -e "${RED}KHÔNG THẤY BRANCH${NC}"
    echo -e "  ${RED}[LỖI]${NC} Repo tồn tại nhưng KHÔNG có branch '$branch'."
    echo "         Kiểm tra lại tên branch, hoặc chạy: git ls-remote --heads $url"
    FAILED=$((FAILED + 1)); FAILED_LIST+=("$path: branch '$branch' không tồn tại")
    echo ""
    continue
  fi
  echo -e "${GREEN}OK${NC} (branch '$branch' tồn tại, SHA hiện tại: ${remote_sha:0:7})"

  # ------------------------------------------------------------------------
  # THỰC HIỆN ADD
  # ------------------------------------------------------------------------
  echo "  Đang chạy: git submodule add -b $branch $url $path"
  add_output=$(git submodule add -b "$branch" "$url" "$path" 2>&1)
  add_status=$?

  if [ $add_status -ne 0 ]; then
    echo -e "  ${RED}[LỖI ADD]${NC} git submodule add thất bại:"
    echo "$add_output" | sed 's/^/         /'
    FAILED=$((FAILED + 1)); FAILED_LIST+=("$path: git submodule add lỗi")
    echo ""
    continue
  fi

  # ------------------------------------------------------------------------
  # KIỂM TRA 4: đối chiếu SHA local vừa checkout với SHA remote đã hỏi
  # ------------------------------------------------------------------------
  local_sha=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo "")
  remote_sha_only=$(echo "$remote_sha" | awk '{print $1}')

  if [ "$local_sha" = "$remote_sha_only" ]; then
    echo -e "  ${GREEN}[OK]${NC} Add thành công. Local đang ở SHA ${local_sha:0:7}, khớp remote."
  else
    echo -e "  ${YELLOW}[CẢNH BÁO]${NC} Add xong nhưng SHA local (${local_sha:0:7}) không khớp"
    echo "               SHA remote đã kiểm tra trước đó (${remote_sha_only:0:7})."
    echo "               Có thể remote vừa có commit mới trong lúc chạy — không sao,"
    echo "               chạy update_submodules.sh sau đó sẽ pin đúng commit cần thiết."
  fi
  OK=$((OK + 1))

  echo ""
done < "$CONF_FILE"

# --------------------------------------------------------------------------
# TỔNG KẾT
# --------------------------------------------------------------------------
echo -e "${BLUE}== Tổng kết ==${NC}"
echo -e "  Tổng dòng xử lý : $TOTAL"
echo -e "  ${GREEN}Add thành công  : $OK${NC}"
echo -e "  ${YELLOW}Bỏ qua (SKIP)   : $SKIPPED${NC}"
echo -e "  ${RED}Lỗi             : $FAILED${NC}"

if [ "${#FAILED_LIST[@]}" -gt 0 ]; then
  echo ""
  echo -e "${RED}Chi tiết các dòng lỗi:${NC}"
  for item in "${FAILED_LIST[@]}"; do
    echo "  - $item"
  done
fi

if [ "$OK" -gt 0 ]; then
  echo ""
  echo -e "${YELLOW}Bước tiếp theo:${NC}"
  echo "  1. git status   (xem lại .gitmodules + các submodule vừa add)"
  echo "  2. Chạy ./update_submodules.sh để pin đúng commit hash theo config"
  echo "  3. git commit -m \"add submodules\" && git push"
fi