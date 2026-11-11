# shellcheck shell=bash
# scripts/smoke.sh 的一项一项探测，跟着插件走。没写的项会 FAIL 并给出写法，不会默认放行。
#
# 变量别叫 state：shellcheck 把这份文件连着 probes.sh 一起分析，probes.sh 自己也读一个 dev.sh 提供的 state；
# 子壳体函数（fn() ( … )）里给 state 赋值，SC2031 就报在 probes.sh 上，CI 红。
#
# 变量：SMOKE_WEB_URL 是应用的网页入口（套件已去尾斜杠，但可能带路径，比如 SSO 登录页）；
#       拼 API 路径用 SMOKE_WEB_ORIGIN（只有 scheme://host:port，入口的路径不掺进来），别直接接在 SMOKE_WEB_URL 后面。
#
# 页面：web_assert 从标准输入读页面，命中的确是应用的真实页面时返回 0。
# 身份：glance 没有用户体系，网页由云吞网关的会话保护，应用自己不再登录；身份项不适用。
# 数据：glance 的配置即数据。data_write 往数据目录里的 glance.yml 追加一个带随机标记的页面，
#       data_check 在重装后按 slug 打开那个页，页面在就说明用户改过的配置原样保留。
_container() { # <插件 id> <服务名>：本实例里这个服务的容器
  local inst="${SMOKE_INSTANCE:-}" args=(--filter "label=wonton.plugin=$1" --filter "label=wonton.service=$2")
  if [[ -z "$inst" && -n "${SMOKE_BASE:-}" ]]; then
    inst="${SMOKE_BASE#http://}"; inst="${inst%%.*}"
  fi
  [[ -z "$inst" ]] || args+=(--filter "label=wonton.instance=${inst//-/}")
  docker ps --format '{{.Names}}' "${args[@]}" | head -1
}

web_assert() { grep -qi 'glance'; }   # 应用自己的页面（默认页的品牌名和资源路径都带 glance）

data_write() {
  local c marker
  c="$(_container "$SMOKE_PLUGIN_ID" glance)"
  [[ -n "$c" ]] || { echo "找不到 glance 容器"; return 1; }
  marker="wonton-$SMOKE_INSTANCE-$RANDOM$RANDOM"
  docker exec -i "$c" sh -c 'cat >> /app/config/glance.yml' <<YAML

  - name: $marker
    slug: $marker
    columns:
      - size: full
        widgets:
          - type: clock
            hour-format: 24h
            timezones:
              - timezone: UTC
                label: $marker
YAML
  echo "$marker" >"$SMOKE_STATE"
}

data_check() {
  local marker page
  marker="$(cat "$SMOKE_STATE")"
  [[ -n "$marker" ]] || { echo "没有数据标记"; return 1; }
  page="$(dweb "/$marker")" || { echo "打开标记页失败：$page"; return 1; }
  grep -qF "$marker" <<<"$page" || { echo "重装后找不到标记页 $marker：$(head -c 200 <<<"$page")"; return 1; }
}
